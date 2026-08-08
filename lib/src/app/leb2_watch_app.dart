import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_configuration.dart';
import '../core/network/backend_compatibility.dart';
import '../core/network/backend_compatibility_coordinator.dart';
import '../core/session/session_lifecycle.dart';
import '../features/assignments/detail/presentation/assignment_detail_route.dart';
import '../features/background_sync/application/background_monitoring_lifecycle.dart';
import '../features/notifications/application/notification_navigation_coordinator.dart';
import '../features/notifications/domain/local_notification_service.dart';
import '../platform/desktop/runtime/desktop_runtime_host.dart';
import 'app_dependencies.dart';
import 'design_system/app_theme.dart';
import 'routing/app_flow.dart';
import 'routing/app_router.dart';

class Leb2WatchApp extends ConsumerStatefulWidget {
  const Leb2WatchApp({required this.configuration, super.key});

  final AppConfiguration configuration;

  @override
  ConsumerState<Leb2WatchApp> createState() => _Leb2WatchAppState();
}

class _Leb2WatchAppState extends ConsumerState<Leb2WatchApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  late final NotificationNavigationCoordinator _notificationNavigation;
  AppLifecycleState? _lastLifecycleState;
  SessionLifecycleSnapshot? _pendingSession;
  SessionLifecycleSnapshot? _processingSession;
  SessionLifecycleSnapshot? _lastHandledSession;
  Future<void>? _sessionLifecycleDrain;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastLifecycleState = WidgetsBinding.instance.lifecycleState;
    final flowController = ref.read(appFlowControllerProvider);
    final notifications = ref.read(localNotificationServiceProvider);
    final windowReveal = ref.read(desktopWindowRevealSignalProvider);
    final compatibility = ref.read(backendCompatibilityControllerProvider);
    BackendCompatibilityCoordinator? compatibilityCoordinator;
    try {
      compatibilityCoordinator = ref.read(
        backendCompatibilityCoordinatorProvider,
      );
    } on Object {
      // Test and recovery shells may omit network configuration.
    }
    _router = createAppRouter(
      flowController,
      compatibilityController: compatibility,
      compatibilityCoordinator: compatibilityCoordinator,
    );
    _notificationNavigation = NotificationNavigationCoordinator(
      notifications,
      flowController,
      (key) {
        windowReveal.requestReveal();
        _router.goNamed(
          assignmentDetailRouteName,
          pathParameters: key.pathParameters,
        );
      },
    );
    unawaited(_initializeNotifications(notifications));
    unawaited(_loadBackendCompatibility());
  }

  Future<void> _loadBackendCompatibility() async {
    final controller = ref.read(backendCompatibilityControllerProvider);
    try {
      final version = await ref.read(clientVersionProvider).readVersion();
      final metadata = await ref
          .read(backendCompatibilityClientProvider)
          .getMetadata();
      controller.setSnapshot(
        evaluateBackendCompatibility(
          installedClientVersion: version,
          metadata: metadata,
        ),
      );
    } on Object {
      controller.setSnapshot(const BackendCompatibilitySnapshot.unavailable());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _lastLifecycleState;
    _lastLifecycleState = state;
    if (state == AppLifecycleState.resumed &&
        previous != null &&
        previous != AppLifecycleState.resumed) {
      unawaited(_handleAppResume());
    }
  }

  Future<BackgroundMonitoringLifecycle?> _backgroundLifecycle() async {
    try {
      return await ref.read(backgroundMonitoringLifecycleProvider.future);
    } on Object {
      return null;
    }
  }

  Future<void> _reconcileBackgroundSchedule(
    SessionLifecycleSnapshot session,
  ) async {
    final lifecycle = await _backgroundLifecycle();
    if (lifecycle != null) {
      await lifecycle.reconcileSession(session);
    }
    if (mounted) {
      ref.read(backgroundScheduleStatusRefreshSignalProvider).requestRefresh();
    }
  }

  void _queueSessionLifecycle(SessionLifecycleSnapshot session) {
    final newestRevision =
        [
          _lastHandledSession?.revision,
          _processingSession?.revision,
          _pendingSession?.revision,
        ].whereType<int>().fold<int>(
          -1,
          (value, item) => item > value ? item : value,
        );
    if (session.revision < newestRevision ||
        session == _lastHandledSession ||
        session == _processingSession ||
        session == _pendingSession) {
      return;
    }
    _pendingSession = session;
    _sessionLifecycleDrain ??= _drainSessionLifecycle();
  }

  Future<void> _drainSessionLifecycle() async {
    try {
      while (mounted && _pendingSession != null) {
        final current = _pendingSession!;
        _pendingSession = null;
        _processingSession = current;
        await _reconcileBackgroundSchedule(current);
        final pending = _pendingSession;
        final superseded =
            pending != null &&
            pending != current &&
            pending.revision >= current.revision;
        if (current.state == SessionLifecycleState.expired && !superseded) {
          try {
            final automatic = await ref.read(
              automaticSessionReauthenticationServiceProvider.future,
            );
            await automatic.reauthenticate(
              expectedExpiredRevision: current.revision,
            );
          } on Object {
            // Durable state keeps cached content available if recovery cannot
            // initialize.
          }
        }
        _lastHandledSession = current;
        _processingSession = null;
      }
    } finally {
      _processingSession = null;
      _sessionLifecycleDrain = null;
      if (mounted && _pendingSession != null) {
        _sessionLifecycleDrain = _drainSessionLifecycle();
      }
    }
  }

  Future<void> _handleAppResume() async {
    final lifecycle = await _backgroundLifecycle();
    if (lifecycle != null) {
      await lifecycle.handleAppResume();
    }
    if (mounted) {
      ref.read(backgroundScheduleStatusRefreshSignalProvider).requestRefresh();
    }
    try {
      final deadlineDelivery = await ref.read(
        desktopDeadlineReminderDeliveryCoordinatorProvider.future,
      );
      await deadlineDelivery?.refresh(permissionMayHaveChanged: true);
    } on Object {
      // A later wall-clock checkpoint retries durable local reminder work.
    }
    await _refreshExactAlarmSchedules();
  }

  Future<void> _initializeNotifications(
    LocalNotificationService notifications,
  ) async {
    try {
      await notifications.initialize();
      final drain = await ref.read(
        newAssignmentNotificationDrainProvider.future,
      );
      await drain.drainActiveCached();
    } on Object {
      // Startup remains local-first when the OS notification bridge is absent.
    }
    await _refreshExactAlarmSchedules();
  }

  Future<void> _refreshExactAlarmSchedules() async {
    try {
      final recovery = ref.read(exactAlarmScheduleRecoveryProvider);
      await recovery.refresh();
    } on Object {
      // Foreground startup or the next resume retries durable reconciliation.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionLifecycleProvider, (_, next) {
      next.whenData((session) {
        _queueSessionLifecycle(session);
      });
    });
    return MaterialApp.router(
      title: 'LEB2 Watch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      themeAnimationStyle: AnimationStyle.noAnimation,
      routerConfig: _router,
      builder: (context, child) {
        return DesktopRuntimeHost(child: child ?? const SizedBox.shrink());
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationNavigation.dispose();
    _router.dispose();
    super.dispose();
  }
}
