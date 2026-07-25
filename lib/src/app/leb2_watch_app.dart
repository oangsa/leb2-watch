import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_configuration.dart';
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

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(ref.read(appFlowControllerProvider));
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
    _router.dispose();
    super.dispose();
  }
}
