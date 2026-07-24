import 'package:flutter/material.dart';

import '../core/config/app_configuration.dart';

class Leb2WatchApp extends StatelessWidget {
  const Leb2WatchApp({required this.configuration, super.key});

  final AppConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'LEB2 Watch',
      home: Scaffold(
        body: SafeArea(child: Center(child: Text('LEB2 Watch'))),
      ),
    );
  }
}
