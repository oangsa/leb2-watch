import 'package:flutter/material.dart';

import '../app_status_colors.dart';
import '../app_tokens.dart';

enum _AppStateKind { loading, empty, error }

class AppStateView extends StatelessWidget {
  const AppStateView.loading({this.title = 'Loading', this.message, super.key})
    : _kind = _AppStateKind.loading,
      actionLabel = null,
      onAction = null;

  const AppStateView.empty({
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert((actionLabel == null) == (onAction == null)),
       _kind = _AppStateKind.empty;

  const AppStateView.error({
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert((actionLabel == null) == (onAction == null)),
       _kind = _AppStateKind.error;

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _AppStateKind _kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = AppStatusColors.of(context);
    final isLoading = _kind == _AppStateKind.loading;
    final isError = _kind == _AppStateKind.error;
    final foregroundColor = isError
        ? statusColors.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    final icon = switch (_kind) {
      _AppStateKind.loading => Icons.hourglass_top_rounded,
      _AppStateKind.empty => Icons.inbox_outlined,
      _AppStateKind.error => Icons.error_outline_rounded,
    };
    final semanticState = switch (_kind) {
      _AppStateKind.loading => 'Loading',
      _AppStateKind.empty => 'Empty',
      _AppStateKind.error => 'Error',
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizing.stateContentMaxWidth,
          ),
          child: Semantics(
            key: const Key('app-state-semantics'),
            container: true,
            explicitChildNodes: true,
            liveRegion: isLoading || isError,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading && !MediaQuery.disableAnimationsOf(context))
                  const ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: AppSizing.stateIcon,
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      key: isLoading
                          ? const Key('app-state-static-loading-icon')
                          : null,
                      color: foregroundColor,
                      size: AppSizing.stateIcon,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  header: !isLoading,
                  label: '$semanticState: $title',
                  child: ExcludeSemantics(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: foregroundColor,
                      ),
                    ),
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: foregroundColor,
                    ),
                  ),
                ],
                if (actionLabel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
