import 'dart:collection';

import '../data/new_assignment_notification_store.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';

final class NewAssignmentNotificationCoordinator {
  NewAssignmentNotificationCoordinator(this._store, this._service);

  static const int completedOperationRetention = 128;

  final NewAssignmentNotificationStore _store;
  final LocalNotificationService _service;
  final Map<(int, int), Future<void>> _inFlight = {};
  final Set<(int, int)> _completed = {};
  final ListQueue<(int, int)> _completedOrder = ListQueue();
  Future<void> _tail = Future.value();

  Future<void> processCommittedSuccess({
    required int semesterId,
    required int operationId,
    bool backgroundTriggered = false,
  }) {
    final key = (semesterId, operationId);
    if (_completed.contains(key)) {
      return Future.value();
    }
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final prior = _tail;
    late final Future<void> tracked;
    tracked =
        _runAfter(
          prior,
          semesterId,
          backgroundTriggered: backgroundTriggered,
        ).whenComplete(() {
          if (identical(_inFlight[key], tracked)) {
            _inFlight.remove(key);
          }
          _rememberCompleted(key);
        });
    _inFlight[key] = tracked;
    _tail = tracked;
    return tracked;
  }

  Future<void> _runAfter(
    Future<void> prior,
    int semesterId, {
    required bool backgroundTriggered,
  }) async {
    try {
      await prior;
      await _sweep(semesterId, backgroundTriggered: backgroundTriggered);
    } on Object {
      // Notification work never poisons later committed synchronization work.
    }
  }

  Future<void> _sweep(
    int semesterId, {
    required bool backgroundTriggered,
  }) async {
    try {
      await _service.initialize();
    } on Object {
      return;
    }

    while (true) {
      final NewAssignmentNotificationClaim? claim;
      try {
        claim = await _store.claimNext(
          semesterId: semesterId,
          backgroundTriggered: backgroundTriggered,
        );
      } on Object {
        return;
      }
      if (claim == null) {
        return;
      }
      final request = claim.request;
      if (request == null) {
        continue;
      }
      try {
        await _service.showNewAssignment(request);
      } on LocalNotificationFailure catch (failure) {
        if (failure.kind == LocalNotificationFailureKind.invalidRequest) {
          continue;
        }
        return;
      } on Object {
        return;
      }
    }
  }

  void _rememberCompleted((int, int) key) {
    if (!_completed.add(key)) {
      return;
    }
    _completedOrder.addLast(key);
    while (_completedOrder.length > completedOperationRetention) {
      _completed.remove(_completedOrder.removeFirst());
    }
  }

  @override
  String toString() => 'NewAssignmentNotificationCoordinator(redacted: true)';
}
