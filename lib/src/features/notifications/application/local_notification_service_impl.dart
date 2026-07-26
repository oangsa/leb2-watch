import 'dart:async';

import '../data/local_notifications_platform.dart';
import '../domain/local_notification_id_factory.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_payload_codec.dart';
import '../domain/local_notification_service.dart';
import 'local_notification_deadline_formatter.dart';

final class LocalNotificationServiceImpl
    implements
        LocalNotificationService,
        LocalNotificationInitializationControl {
  LocalNotificationServiceImpl(
    this._platform, {
    this._payloadCodec = const LocalNotificationPayloadCodec(),
    this._deadlineFormatter = const DeviceLocalNotificationDeadlineFormatter(),
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? _systemUtcNow;

  static const int _maximumCourseNameLength = 80;
  static const int _maximumAssignmentTitleLength = 160;
  static final RegExp _unsafeDisplayCharacter = RegExp(
    '[\\u0000-\\u001F\\u007F-\\u009F\\u061C\\u200E\\u200F'
    '\\u202A-\\u202E\\u2066-\\u2069]',
  );

  final LocalNotificationsPlatform _platform;
  final LocalNotificationPayloadCodec _payloadCodec;
  final LocalNotificationDeadlineFormatter _deadlineFormatter;
  final DateTime Function() _nowUtc;
  final StreamController<LocalNotificationTarget> _responses =
      StreamController<LocalNotificationTarget>.broadcast(sync: true);

  _InitializationAttemptState? _initializeAttempt;
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<LocalNotificationTarget> get responses => _responses.stream;

  @override
  Future<void> initialize() => beginInitializationAttempt().completion;

  @override
  LocalNotificationInitializationAttempt beginInitializationAttempt() {
    if (_disposed) {
      return _ImmediateInitializationAttempt(
        Future<void>.error(
          const LocalNotificationFailure(
            LocalNotificationFailureKind.notInitialized,
          ),
        ),
      );
    }
    final existing = _initializeAttempt;
    if (existing != null) {
      return _InitializationAttemptHandle(this, existing);
    }

    final attempt = _InitializationAttemptState();
    _initializeAttempt = attempt;
    _initialized = false;
    unawaited(Future<void>.microtask(() => _performInitialization(attempt)));
    return _InitializationAttemptHandle(this, attempt);
  }

  Future<void> _performInitialization(
    _InitializationAttemptState attempt,
  ) async {
    try {
      _throwIfDisposed();
      final initialized = await _platform.initialize(
        onResponse: (payload) {
          if (_isCurrentInitialization(attempt)) {
            _handlePayload(payload);
          }
        },
      );
      if (!_isCurrentInitialization(attempt)) {
        return;
      }
      if (initialized != true) {
        throw const LocalNotificationFailure(
          LocalNotificationFailureKind.platformUnavailable,
        );
      }
      _throwIfDisposed();

      String? launchPayload;
      if (_platform.capabilities.supportsLaunchPayload) {
        launchPayload = await _platform.getLaunchPayload();
        if (!_isCurrentInitialization(attempt)) {
          return;
        }
        _throwIfDisposed();
      }

      _initialized = true;
      _handlePayload(launchPayload);
      attempt.complete();
    } on LocalNotificationFailure catch (failure) {
      _completeInitializationFailure(attempt, failure);
    } on Object {
      _completeInitializationFailure(
        attempt,
        const LocalNotificationFailure(
          LocalNotificationFailureKind.platformFailure,
        ),
      );
    }
  }

  bool _isCurrentInitialization(_InitializationAttemptState attempt) {
    return identical(_initializeAttempt, attempt);
  }

  void _completeInitializationFailure(
    _InitializationAttemptState attempt,
    LocalNotificationFailure failure,
  ) {
    if (!_isCurrentInitialization(attempt)) {
      return;
    }
    _initialized = false;
    _initializeAttempt = null;
    attempt.completeError(failure);
  }

  void _abandonInitialization(_InitializationAttemptState attempt) {
    if (!_isCurrentInitialization(attempt) || attempt.isCompleted) {
      return;
    }
    _initialized = false;
    _initializeAttempt = null;
    attempt.completeError(
      const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      ),
    );
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async {
    _requireInitialized();
    try {
      return await _platform.readDeliveryPermission();
    } on Object {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      );
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    _requireInitialized();
    final capabilities = _platform.capabilities;
    if (!capabilities.requiresPermissionRequest) {
      return capabilities.supportsImmediate
          ? NotificationPermissionStatus.notRequired
          : NotificationPermissionStatus.unavailable;
    }

    try {
      return switch (await _platform.requestPermission()) {
        true => NotificationPermissionStatus.granted,
        false => NotificationPermissionStatus.denied,
        null => NotificationPermissionStatus.unavailable,
      };
    } on Object {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      );
    }
  }

  @override
  Future<void> showTestNotification() async {
    _requireInitialized();
    _requireCapability(_platform.capabilities.supportsImmediate);
    await _show(
      const PlatformNotification(
        id: LocalNotificationIdFactory.testNotificationId,
        kind: PlatformNotificationKind.test,
        title: 'LEB2 Watch',
        body: 'Local notifications are working on this device.',
        payload: null,
        groupKey: null,
      ),
    );
  }

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {
    _requireInitialized();
    _requireCapability(_platform.capabilities.supportsImmediate);
    _validateNewAssignmentOwner(request);
    final courseName = _boundedSingleLine(
      request.courseName,
      maximumLength: _maximumCourseNameLength,
    );
    final assignmentTitle = _boundedSingleLine(
      request.assignmentTitle,
      maximumLength: _maximumAssignmentTitleLength,
    );
    if (request.courseId <= 0 || request.courseId > 2147483647) {
      _invalidRequest();
    }
    final deadline = request.deadlineAtUtc;
    if (deadline != null && !deadline.isUtc) {
      _invalidRequest();
    }

    final payload = _payloadCodec.encode(
      LocalNotificationTarget.assignment(request.assignment),
    );
    final dueCopy = deadline == null
        ? ''
        : '\nDue: ${_deadlineFormatter.format(deadline)}';
    await _show(
      PlatformNotification(
        id: request.id.value,
        kind: PlatformNotificationKind.newAssignment,
        title: courseName,
        body: 'New assignment: $assignmentTitle$dueCopy',
        payload: payload,
        groupKey:
            'leb2.course.${request.assignment.semesterId}.${request.courseId}',
      ),
    );
  }

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {
    _requireInitialized();
    _requireCapability(_platform.capabilities.supportsScheduling);
    _validateReminderOwner(request);
    final courseName = _boundedSingleLine(
      request.courseName,
      maximumLength: _maximumCourseNameLength,
    );
    final assignmentTitle = _boundedSingleLine(
      request.assignmentTitle,
      maximumLength: _maximumAssignmentTitleLength,
    );
    if (request.courseId <= 0 ||
        request.courseId > 2147483647 ||
        request.offsetMinutes <= 0 ||
        !request.deadlineAtUtc.isUtc ||
        !request.scheduledForUtc.isUtc ||
        !request.scheduledForUtc.isAfter(_nowUtc()) ||
        request.deadlineAtUtc.difference(request.scheduledForUtc) !=
            Duration(minutes: request.offsetMinutes)) {
      _invalidRequest();
    }

    final payload = _payloadCodec.encode(
      LocalNotificationTarget.assignment(request.assignment),
    );
    await _schedule(
      PlatformScheduledNotification(
        notification: PlatformNotification(
          id: request.id.value,
          kind: PlatformNotificationKind.deadlineReminder,
          title: courseName,
          body:
              'Due soon: $assignmentTitle\n'
              'Due: ${_deadlineFormatter.format(request.deadlineAtUtc)}',
          payload: payload,
          groupKey:
              'leb2.course.${request.assignment.semesterId}.'
              '${request.courseId}',
        ),
        scheduledForUtc: request.scheduledForUtc,
        precision: PlatformSchedulePrecision.inexact,
      ),
    );
  }

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {
    _requireInitialized();
    _requireCapability(_platform.capabilities.supportsCancellation);
    if (id.owner.kind != NotificationKind.deadlineReminder) {
      _invalidRequest();
    }
    try {
      await _platform.cancel(id.value);
    } on Object {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    _requireInitialized();
    _requireCapability(_platform.capabilities.supportsCancellation);
    try {
      await _platform.cancelAll();
    } on Object {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      );
    }
  }

  Future<void> _show(PlatformNotification notification) async {
    try {
      await _platform.show(notification);
    } on Object {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      );
    }
  }

  Future<void> _schedule(PlatformScheduledNotification notification) async {
    try {
      await _platform.schedule(notification);
    } on Object {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.platformFailure,
      );
    }
  }

  void _validateNewAssignmentOwner(NewAssignmentNotification request) {
    final owner = request.id.owner;
    if (owner.kind != NotificationKind.newAssignment ||
        owner.assignment != request.assignment ||
        owner.offsetMinutes != null) {
      _invalidRequest();
    }
  }

  void _validateReminderOwner(DeadlineReminderNotification request) {
    final owner = request.id.owner;
    if (owner.kind != NotificationKind.deadlineReminder ||
        owner.assignment != request.assignment ||
        owner.offsetMinutes != request.offsetMinutes) {
      _invalidRequest();
    }
  }

  String _boundedSingleLine(String value, {required int maximumLength}) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty ||
        normalized.length > maximumLength ||
        _unsafeDisplayCharacter.hasMatch(normalized)) {
      _invalidRequest();
    }
    return normalized;
  }

  void _handlePayload(String? payload) {
    if (_disposed || payload == null) {
      return;
    }
    final target = _payloadCodec.decode(payload);
    if (target == null) {
      return;
    }
    _responses.add(target);
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.notInitialized,
      );
    }
  }

  void _requireInitialized() {
    if (_disposed || !_initialized) {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.notInitialized,
      );
    }
  }

  void _requireCapability(bool supported) {
    if (!supported) {
      throw const LocalNotificationFailure(
        LocalNotificationFailureKind.unsupported,
      );
    }
  }

  Never _invalidRequest() {
    throw const LocalNotificationFailure(
      LocalNotificationFailureKind.invalidRequest,
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _platform.dispose();
    unawaited(_responses.close());
  }

  @override
  String toString() => 'LocalNotificationService(redacted: true)';
}

DateTime _systemUtcNow() => DateTime.now().toUtc();

final class _InitializationAttemptState {
  final Completer<void> _completion = Completer<void>();

  Future<void> get completion => _completion.future;

  bool get isCompleted => _completion.isCompleted;

  void complete() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  void completeError(LocalNotificationFailure failure) {
    if (!_completion.isCompleted) {
      _completion.completeError(failure);
    }
  }
}

final class _InitializationAttemptHandle
    implements LocalNotificationInitializationAttempt {
  const _InitializationAttemptHandle(this._owner, this._attempt);

  final LocalNotificationServiceImpl _owner;
  final _InitializationAttemptState _attempt;

  @override
  Future<void> get completion => _attempt.completion;

  @override
  void abandon() => _owner._abandonInitialization(_attempt);
}

final class _ImmediateInitializationAttempt
    implements LocalNotificationInitializationAttempt {
  const _ImmediateInitializationAttempt(this.completion);

  @override
  final Future<void> completion;

  @override
  void abandon() {}
}
