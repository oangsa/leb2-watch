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

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;

  void _selectDestination(int index) {
    navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    return switch (AppBreakpoints.of(context)) {
      AppWindowClass.compact => _CompactShell(
        navigationShell: navigationShell,
        globalBanner: globalBanner,
        onDestinationSelected: _selectDestination,
      ),
      AppWindowClass.medium => _MediumShell(
        navigationShell: navigationShell,
        globalBanner: globalBanner,
        onDestinationSelected: _selectDestination,
      ),
      AppWindowClass.expanded => _ExpandedShell(
        navigationShell: navigationShell,
        globalBanner: globalBanner,
        onDestinationSelected: _selectDestination,
      ),
    };
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.navigationShell,
    required this.globalBanner,
    required this.onDestinationSelected,
  });

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: AdaptiveAppShell.compactKey,
      body: _ShellContent(globalBanner: globalBanner, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        key: AdaptiveAppShell.compactNavigationKey,
        selectedIndex: navigationShell.currentIndex,
        labelBehavior: _compactLabelBehavior(context),
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
  });

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;
  final ValueChanged<int> onDestinationSelected;

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
  });

  final StatefulNavigationShell navigationShell;
  final Widget? globalBanner;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
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
                  child: Text(
                    'LEB2 Watch',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                onDestinationSelected: onDestinationSelected,
                destinations: _railDestinations('expanded'),
              ),
              const VerticalDivider(),
              Expanded(
                child: _ShellContent(
                  globalBanner: globalBanner,
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
  const _ShellContent({required this.globalBanner, required this.child});

  final Widget? globalBanner;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final banner = globalBanner;
    if (banner == null) {
      return child;
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: banner,
        ),
        Expanded(child: child),
      ],
    );
  }
}

NavigationDestinationLabelBehavior _compactLabelBehavior(BuildContext context) {
  final theme = Theme.of(context);
  final navigationTheme = NavigationBarTheme.of(context);
  final selectedLabelStyle =
      navigationTheme.labelTextStyle?.resolve({WidgetState.selected}) ??
      theme.textTheme.labelMedium ??
      const TextStyle(fontSize: AppTypography.labelMediumSize);
  final fontSize = selectedLabelStyle.fontSize ?? AppTypography.labelMediumSize;
  final textScaler = MediaQuery.textScalerOf(context);

  if (textScaler.scale(fontSize) > fontSize) {
    return NavigationDestinationLabelBehavior.alwaysHide;
  }

  final destinationWidth =
      MediaQuery.sizeOf(context).width / AppDestination.values.length;
  for (final destination in AppDestination.values) {
    final painter = TextPainter(
      text: TextSpan(text: destination.label, style: selectedLabelStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final fits = painter.width <= destinationWidth;
    painter.dispose();
    if (!fits) {
      return NavigationDestinationLabelBehavior.alwaysHide;
    }
  }

  return NavigationDestinationLabelBehavior.onlyShowSelected;
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
    LogicalKeyboardKey.digit4,
  ];

  return {
    for (var index = 0; index < keys.length; index++)
      SingleActivator(keys[index], meta: useMeta, control: !useMeta): () =>
          onDestinationSelected(index),
  };
}
