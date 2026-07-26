import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_configuration.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastLifecycleState = WidgetsBinding.instance.lifecycleState;
    final flowController = ref.read(appFlowControllerProvider);
    final notifications = ref.read(localNotificationServiceProvider);
    _router = createAppRouter(flowController);
    _notificationNavigation = NotificationNavigationCoordinator(
      notifications,
      flowController,
      (key) {
        _router.goNamed(
          assignmentDetailRouteName,
          pathParameters: key.pathParameters,
        );
      },
    );
    unawaited(_initializeNotifications(notifications));
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

  Future<void> _handleAppResume() async {
    final lifecycle = await _backgroundLifecycle();
    if (lifecycle != null) {
      await lifecycle.handleAppResume();
    }
    if (mounted) {
      ref.read(backgroundScheduleStatusRefreshSignalProvider).requestRefresh();
    }
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
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionLifecycleProvider, (_, next) {
      next.whenData((session) {
        unawaited(_reconcileBackgroundSchedule(session));
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
