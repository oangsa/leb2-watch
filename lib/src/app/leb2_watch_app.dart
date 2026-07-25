import 'package:flutter/material.dart';

import '../core/config/app_configuration.dart';
import 'design_system/app_theme.dart';

class Leb2WatchApp extends StatelessWidget {
  const Leb2WatchApp({required this.configuration, super.key});

  final AppConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEB2 Watch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      themeAnimationStyle: AnimationStyle.noAnimation,
      home: const Scaffold(
        body: SafeArea(child: Center(child: Text('LEB2 Watch'))),
      ),
    );
  }
}
