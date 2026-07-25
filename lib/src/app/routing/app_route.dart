import 'package:flutter/material.dart';

enum AppRoute {
  onboarding('/onboarding'),
  authentication('/authentication'),
  semesters('/semesters'),
  assignments('/assignments'),
  courses('/courses'),
  settings('/settings'),
  diagnostics('/diagnostics'),
  privacy('/privacy');

  const AppRoute(this.path);

  final String path;
}

enum AppDestination {
  assignments(
    route: AppRoute.assignments,
    label: 'Assignments',
    icon: Icons.assignment_outlined,
    selectedIcon: Icons.assignment,
  ),
  courses(
    route: AppRoute.courses,
    label: 'Courses',
    icon: Icons.school_outlined,
    selectedIcon: Icons.school,
  ),
  settings(
    route: AppRoute.settings,
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
  diagnostics(
    route: AppRoute.diagnostics,
    label: 'Diagnostics',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart,
  );

  const AppDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final AppRoute route;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
