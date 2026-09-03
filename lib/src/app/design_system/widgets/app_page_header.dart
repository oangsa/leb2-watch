import 'package:flutter/material.dart';

import '../app_tokens.dart';

/// Shared page header used by the primary work areas.
///
/// Keeping the surface, spacing, and type in one widget prevents each tab from
/// growing a subtly different header treatment.
final class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    required this.semesterLabel,
    this.supportingText,
    this.supportingKey,
    this.trailing,
    super.key,
  });

  final String title;
  final String semesterLabel;
  final String? supportingText;
  final Key? supportingKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.panel),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            trailing == null ? AppSpacing.lg : AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.headlineMedium),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      semesterLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (supportingText != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        supportingText!,
                        key: supportingKey,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
