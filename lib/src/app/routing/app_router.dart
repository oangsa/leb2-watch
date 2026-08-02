import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_dependencies.dart';
import '../design_system/widgets/app_status_banner.dart';
import '../design_system/widgets/app_state_view.dart';
import '../shell/adaptive_app_shell.dart';
import '../../core/session/session_lifecycle.dart';
import '../../features/authentication/presentation/session_setup_route.dart';
import '../../features/authentication/domain/automatic_session_reauthentication.dart';
import '../../features/assignments/dashboard/presentation/assignment_dashboard_route.dart';
import '../../features/assignments/detail/presentation/assignment_detail_route.dart';
import '../../features/courses/presentation/course_preferences_route.dart';
import '../../features/diagnostics/presentation/synchronization_diagnostics_route.dart';
import '../../features/onboarding/presentation/privacy_onboarding_page.dart';
import '../../features/privacy/presentation/privacy_page.dart';
import '../../features/semesters/presentation/semester_selection_route.dart';
import '../../features/settings/notifications/presentation/notification_settings_route.dart';
import 'app_flow.dart';
import 'app_route.dart';

GoRouter createAppRouter(
  AppFlowController controller, {
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? AppRoute.assignments.path,
    refreshListenable: controller,
    redirect: (_, state) => _redirectForStage(controller.stage, state.uri.path),
    errorBuilder: (context, _) => Scaffold(
      body: AppStateView.error(
        title: 'Page unavailable',
        message: 'This page could not be opened.',
        actionLabel: 'Open assignments',
        onAction: () => context.go(AppRoute.assignments.path),
      ),
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoute.assignments.path),
      GoRoute(
        name: AppRoute.onboarding.name,
        path: AppRoute.onboarding.path,
        builder: (_, _) => PrivacyOnboardingPage(
          onCompleted: () =>
              controller.updateStage(AppFlowStage.authentication),
        ),
      ),
      GoRoute(
        name: AppRoute.authentication.name,
        path: AppRoute.authentication.path,
        builder: (_, _) => const SessionSetupRoute(),
      ),
      GoRoute(
        name: AppRoute.semesters.name,
        path: AppRoute.semesters.path,
        builder: (_, _) => const SemesterSelectionRoute(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            _SessionAwareShell(navigationShell: navigationShell),
        branches: [
          for (final destination in AppDestination.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  name: destination.route.name,
                  path: destination.route.path,
                  builder: (_, _) => switch (destination) {
                    AppDestination.assignments =>
                      const AssignmentDashboardRoute(),
                    AppDestination.courses => const CoursePreferencesRoute(),
                    AppDestination.settings =>
                      const NotificationSettingsRoute(),
                    AppDestination.diagnostics =>
                      const SynchronizationDiagnosticsRoute(),
                  },
                  routes: destination == AppDestination.assignments
                      ? [
                          GoRoute(
                            name: assignmentDetailRouteName,
                            path: assignmentDetailRoutePath,
                            builder: (_, state) => AssignmentDetailRoute(
                              semesterIdSource:
                                  state.pathParameters['semesterId'] ?? '',
                              identityKeySource:
                                  state.pathParameters['identityKey'] ?? '',
                            ),
                          ),
                        ]
                      : const [],
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        name: AppRoute.privacy.name,
        path: AppRoute.privacy.path,
        builder: (_, _) => const PrivacyPage(),
      ),
    ],
  );
}

String? _redirectForStage(AppFlowStage stage, String requestedPath) {
  if (requestedPath == AppRoute.privacy.path) {
    return null;
  }

  return switch (stage) {
    AppFlowStage.onboarding =>
      requestedPath == AppRoute.onboarding.path
          ? null
          : AppRoute.onboarding.path,
    AppFlowStage.authentication =>
      requestedPath == AppRoute.authentication.path
          ? null
          : AppRoute.authentication.path,
    AppFlowStage.semesterSelection =>
      requestedPath == AppRoute.semesters.path ? null : AppRoute.semesters.path,
    AppFlowStage.ready =>
      requestedPath == '/' || requestedPath == AppRoute.onboarding.path
          ? AppRoute.assignments.path
          : null,
  };
}

class _SessionAwareShell extends ConsumerWidget {
  const _SessionAwareShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifecycle = ref.watch(sessionLifecycleProvider).value;
    final attempt = lifecycle?.state == SessionLifecycleState.expired
        ? ref
              .watch(currentAutomaticSessionReauthenticationAttemptProvider)
              .value
        : null;
    final message = _automaticReconnectMessage(attempt);
    return AdaptiveAppShell(
      navigationShell: navigationShell,
      globalBanner: lifecycle?.state == SessionLifecycleState.expired
          ? message == null
                ? null
                : AppStatusBanner.sessionExpired(
                    key: const Key('session-expired-banner'),
                    message: message,
                    onAction: () => context.push(AppRoute.authentication.path),
                  )
          : null,
    );
  }
}

String? _automaticReconnectMessage(AutomaticReauthenticationAttempt? attempt) {
  if (attempt?.state == AutomaticReauthenticationAttemptState.succeeded) {
    return null;
  }
  if (attempt?.state == AutomaticReauthenticationAttemptState.running) {
    return 'Your LEB2 session expired. Reconnecting securely… '
        'Saved data remains available.';
  }
  return switch (attempt?.failureKind) {
    AutomaticReauthenticationFailureKind.invalidCredentials =>
      'Saved sign-in was not accepted. Reconnect manually.',
    AutomaticReauthenticationFailureKind.notEnabled =>
      'Automatic reconnect is not enabled. Reconnect manually. '
          'Saved data remains available.',
    AutomaticReauthenticationFailureKind.accessKeyMissing ||
    AutomaticReauthenticationFailureKind.accessKeyInvalid =>
      'Automatic reconnect has no valid access key. Reconnect manually. '
          'Saved data remains available.',
    AutomaticReauthenticationFailureKind.accessKeyNotActivated =>
      'This access key is not activated. Use Username / password once, then '
          'reconnect. Saved data remains available.',
    AutomaticReauthenticationFailureKind.accessKeyAccountMismatch =>
      'This access key cannot be used with this LEB2 account. Reconnect with '
          'the correct key. Saved data remains available.',
    AutomaticReauthenticationFailureKind.accessKeyReauthenticationRequired =>
      'This access key needs Username / password reauthentication. Reconnect '
          'manually. Saved data remains available.',
    AutomaticReauthenticationFailureKind.accessKeyStoreUnavailable =>
      'Access-key verification is temporarily unavailable. Try again later. '
          'Saved data remains available.',
    AutomaticReauthenticationFailureKind.cancelled ||
    AutomaticReauthenticationFailureKind.timedOut ||
    AutomaticReauthenticationFailureKind.superseded =>
      'Automatic reconnect was interrupted. Reconnect manually. '
          'Saved data remains available.',
    null => 'Your LEB2 session expired. Showing saved data.',
    _ =>
      'Automatic reconnect failed. Reconnect manually. '
          'Saved data remains available.',
  };
}
