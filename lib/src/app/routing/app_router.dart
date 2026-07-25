import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/widgets/app_state_view.dart';
import '../shell/adaptive_app_shell.dart';
import '../../features/onboarding/presentation/privacy_onboarding_page.dart';
import 'app_flow.dart';
import 'app_placeholder_page.dart';
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
      _placeholderRoute(AppRoute.authentication, 'Authentication'),
      _placeholderRoute(AppRoute.semesters, 'Semesters'),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            AdaptiveAppShell(navigationShell: navigationShell),
        branches: [
          for (final destination in AppDestination.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  name: destination.route.name,
                  path: destination.route.path,
                  builder: (_, _) => AppPlaceholderSurface(
                    key: Key('${destination.name}-surface'),
                    label: destination.label,
                  ),
                ),
              ],
            ),
        ],
      ),
      _placeholderRoute(AppRoute.privacy, 'Privacy'),
    ],
  );
}

GoRoute _placeholderRoute(AppRoute route, String label) {
  return GoRoute(
    name: route.name,
    path: route.path,
    builder: (_, _) => AppPlaceholderPage(label: label),
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
      requestedPath == '/' ||
              requestedPath == AppRoute.onboarding.path ||
              requestedPath == AppRoute.authentication.path ||
              requestedPath == AppRoute.semesters.path
          ? AppRoute.assignments.path
          : null,
  };
}
