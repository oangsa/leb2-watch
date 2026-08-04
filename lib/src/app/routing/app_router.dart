import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_dependencies.dart';
import '../../core/network/backend_compatibility.dart';
import '../../core/network/backend_compatibility_coordinator.dart';
import '../../core/network/backend_compatibility_controller.dart';
import '../design_system/widgets/app_status_banner.dart';
import '../design_system/widgets/app_state_view.dart';
import '../shell/adaptive_app_shell.dart';
import '../../core/session/session_lifecycle.dart';
import '../../features/authentication/presentation/session_setup_route.dart';
import '../../features/compatibility/presentation/update_required_page.dart';
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
  BackendCompatibilityController? compatibilityController,
  BackendCompatibilityCoordinator? compatibilityCoordinator,
  String? initialLocation,
}) {
  final compatibility =
      compatibilityController ?? BackendCompatibilityController();
  return GoRouter(
    initialLocation: initialLocation ?? AppRoute.assignments.path,
    refreshListenable: Listenable.merge([controller, compatibility]),
    redirect: (_, state) => _redirectForStage(
      controller.stage,
      compatibility.snapshot,
      state.uri.path,
    ),
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
        name: AppRoute.updateRequired.name,
        path: AppRoute.updateRequired.path,
        builder: (_, _) => UpdateRequiredPage(
          snapshot: compatibility.snapshot,
          onRetry:
              compatibilityCoordinator?.refreshMetadata ?? () async => null,
          controller: compatibility,
        ),
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

String? _redirectForStage(
  AppFlowStage stage,
  BackendCompatibilitySnapshot compatibility,
  String requestedPath,
) {
  if (compatibility.blocksRemoteUse) {
    return requestedPath == AppRoute.updateRequired.path
        ? null
        : AppRoute.updateRequired.path;
  }
  if (requestedPath == AppRoute.updateRequired.path) {
    return _redirectForStage(stage, compatibility, '/');
  }
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
    return 'Session expired. Reconnecting… Showing saved data.';
  }
  return switch (attempt?.failureKind) {
    AutomaticReauthenticationFailureKind.invalidCredentials =>
      'Saved sign-in was rejected. Reconnect manually.',
    AutomaticReauthenticationFailureKind.notEnabled =>
      'Automatic reconnect is off. Reconnect manually. Showing saved data.',
    AutomaticReauthenticationFailureKind.accessKeyMissing ||
    AutomaticReauthenticationFailureKind.accessKeyInvalid =>
      'No valid access key. Reconnect manually. Showing saved data.',
    AutomaticReauthenticationFailureKind.accessKeyNotActivated =>
      'Access key not activated. Sign in once with username and password. '
          'Showing saved data.',
    AutomaticReauthenticationFailureKind.accessKeyAccountMismatch =>
      'Access key does not match this account. Showing saved data.',
    AutomaticReauthenticationFailureKind.accessKeyReauthenticationRequired =>
      'Sign in again with username and password. Showing saved data.',
    AutomaticReauthenticationFailureKind.accessKeyStoreUnavailable =>
      'Key check unavailable. Try again later. Showing saved data.',
    AutomaticReauthenticationFailureKind.deviceIdentityMissing ||
    AutomaticReauthenticationFailureKind.deviceIdentityInvalid =>
      'Invalid device identifier. Showing saved data.',
    AutomaticReauthenticationFailureKind.deviceNotBound =>
      'Reconnect this device: sign in with username and password. '
          'Showing saved data.',
    AutomaticReauthenticationFailureKind.deviceMismatch =>
      'Key is bound to another device. Log out there first. '
          'Showing saved data.',
    AutomaticReauthenticationFailureKind.clientVersionRequired ||
    AutomaticReauthenticationFailureKind.clientVersionInvalid =>
      'Invalid client version. Showing saved data.',
    AutomaticReauthenticationFailureKind.clientUpdateRequired =>
      'This version is too old. Install the latest APK.',
    AutomaticReauthenticationFailureKind.cancelled ||
    AutomaticReauthenticationFailureKind.timedOut ||
    AutomaticReauthenticationFailureKind.superseded =>
      'Automatic reconnect was interrupted. Reconnect manually. '
          'Showing saved data.',
    null => 'Session expired. Showing saved data.',
    _ => 'Automatic reconnect failed. Reconnect manually. Showing saved data.',
  };
}
