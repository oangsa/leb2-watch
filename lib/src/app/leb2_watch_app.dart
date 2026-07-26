import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_configuration.dart';
import '../features/assignments/detail/presentation/assignment_detail_route.dart';
import '../features/notifications/application/notification_navigation_coordinator.dart';
import '../features/notifications/domain/local_notification_service.dart';
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

class _Leb2WatchAppState extends ConsumerState<Leb2WatchApp> {
  late final GoRouter _router;
  late final NotificationNavigationCoordinator _notificationNavigation;

  @override
  void initState() {
    super.initState();
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

  Future<void> _initializeNotifications(
    LocalNotificationService notifications,
  ) async {
    try {
      await notifications.initialize();
    } on Object {
      // Startup remains local-first when the OS notification bridge is absent.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LEB2 Watch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      themeAnimationStyle: AnimationStyle.noAnimation,
      routerConfig: _router,
    );
  }

  @override
  void dispose() {
    _notificationNavigation.dispose();
    _router.dispose();
    super.dispose();
  }
}
