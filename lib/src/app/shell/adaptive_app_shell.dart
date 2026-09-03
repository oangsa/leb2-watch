// Hallmark · native app shell: Workbench / modern-minimal Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../design_system/app_breakpoints.dart';
import '../design_system/app_tokens.dart';
import '../routing/app_route.dart';

class AdaptiveAppShell extends StatelessWidget {
  const AdaptiveAppShell({
    required this.navigationShell,
    this.globalBanner,
    super.key,
  });

  static const compactKey = Key('adaptive-shell-compact');
  static const mediumKey = Key('adaptive-shell-medium');
  static const expandedKey = Key('adaptive-shell-expanded');
  static const compactNavigationKey = Key('compact-navigation');
  static const mediumNavigationKey = Key('medium-navigation');
  static const expandedNavigationKey = Key('expanded-navigation');
  static const expandedFocusKey = Key('expanded-navigation-focus');
  static const changeSemesterActionKey = Key('change-semester-action');

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;

  void _selectDestination(int index) {
    navigationShell.goBranch(index);
  }

  void _changeSemester(BuildContext context) {
    context.push(AppRoute.semesters.path);
  }

  @override
  Widget build(BuildContext context) {
    return switch (AppBreakpoints.of(context)) {
      AppWindowClass.compact => _CompactShell(
        navigationShell: navigationShell,
        globalBanner: globalBanner,
        onDestinationSelected: _selectDestination,
        onChangeSemester: () => _changeSemester(context),
      ),
      AppWindowClass.medium => _MediumShell(
        navigationShell: navigationShell,
        globalBanner: globalBanner,
        onDestinationSelected: _selectDestination,
        onChangeSemester: () => _changeSemester(context),
      ),
      AppWindowClass.expanded => _ExpandedShell(
        navigationShell: navigationShell,
        globalBanner: globalBanner,
        onDestinationSelected: _selectDestination,
        onChangeSemester: () => _changeSemester(context),
      ),
    };
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.navigationShell,
    required this.globalBanner,
    required this.onDestinationSelected,
    required this.onChangeSemester,
  });

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onChangeSemester;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: AdaptiveAppShell.compactKey,
      body: _ShellContent(
        globalBanner: globalBanner,
        onChangeSemester: onChangeSemester,
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        key: AdaptiveAppShell.compactNavigationKey,
        selectedIndex: navigationShell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          for (final destination in AppDestination.values)
            NavigationDestination(
              key: Key('compact-${destination.name}'),
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _MediumShell extends StatelessWidget {
  const _MediumShell({
    required this.navigationShell,
    required this.globalBanner,
    required this.onDestinationSelected,
    required this.onChangeSemester,
  });

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onChangeSemester;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: AdaptiveAppShell.mediumKey,
      body: Row(
        children: [
          NavigationRail(
            key: AdaptiveAppShell.mediumNavigationKey,
            selectedIndex: navigationShell.currentIndex,
            labelType: NavigationRailLabelType.all,
            scrollable: true,
            onDestinationSelected: onDestinationSelected,
            destinations: _railDestinations('medium'),
          ),
          const VerticalDivider(),
          Expanded(
            child: _ShellContent(
              globalBanner: globalBanner,
              onChangeSemester: onChangeSemester,
              child: navigationShell,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedShell extends StatelessWidget {
  const _ExpandedShell({
    required this.navigationShell,
    required this.globalBanner,
    required this.onDestinationSelected,
    required this.onChangeSemester,
  });

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onChangeSemester;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: _shortcutBindings(onDestinationSelected),
      child: Focus(
        key: AdaptiveAppShell.expandedFocusKey,
        autofocus: true,
        child: Scaffold(
          key: AdaptiveAppShell.expandedKey,
          body: Row(
            children: [
              NavigationRail(
                key: AdaptiveAppShell.expandedNavigationKey,
                extended: true,
                selectedIndex: navigationShell.currentIndex,
                labelType: NavigationRailLabelType.none,
                scrollable: true,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(AppRadii.control),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Icon(
                            Icons.visibility_outlined,
                            color: theme.colorScheme.onPrimary,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('LEB2 Watch', style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                onDestinationSelected: onDestinationSelected,
                destinations: _railDestinations('expanded'),
              ),
              const VerticalDivider(),
              Expanded(
                child: _ShellContent(
                  globalBanner: globalBanner,
                  onChangeSemester: onChangeSemester,
                  child: navigationShell,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellContent extends StatelessWidget {
  const _ShellContent({
    required this.globalBanner,
    required this.onChangeSemester,
    required this.child,
  });

  final Widget? globalBanner;
  final VoidCallback onChangeSemester;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final banner = globalBanner;
    final scaledText = MediaQuery.textScalerOf(context).scale(1) > 1;
    return Column(
      verticalDirection: VerticalDirection.up,
      children: [
        Expanded(child: child),
        if (banner != null && scaledText)
          Flexible(
            fit: FlexFit.loose,
            child: ListView(
              primary: false,
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              children: [banner],
            ),
          ),
        if (banner != null && !scaledText)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: banner,
          ),
        SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: AdaptiveAppShell.changeSemesterActionKey,
                onPressed: onChangeSemester,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Change semester'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<NavigationRailDestination> _railDestinations(String layout) {
  return [
    for (final destination in AppDestination.values)
      NavigationRailDestination(
        icon: Icon(destination.icon),
        selectedIcon: Icon(destination.selectedIcon),
        label: Text(destination.label, key: Key('$layout-${destination.name}')),
      ),
  ];
}

Map<ShortcutActivator, VoidCallback> _shortcutBindings(
  ValueChanged<int> onDestinationSelected,
) {
  final useMeta =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final keys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
  ];

  return {
    for (var index = 0; index < keys.length; index++)
      SingleActivator(keys[index], meta: useMeta, control: !useMeta): () =>
          onDestinationSelected(index),
  };
}
