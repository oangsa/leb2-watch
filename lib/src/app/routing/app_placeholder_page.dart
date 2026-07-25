import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

class AppPlaceholderPage extends StatelessWidget {
  const AppPlaceholderPage({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LEB2 Watch')),
      body: AppPlaceholderSurface(label: label),
    );
  }
}

class AppPlaceholderSurface extends StatelessWidget {
  const AppPlaceholderSurface({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Semantics(
            header: true,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
      ),
    );
  }
}
