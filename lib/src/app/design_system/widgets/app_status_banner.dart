import 'package:flutter/material.dart';

import '../app_status_colors.dart';
import '../app_tokens.dart';

enum _AppStatusBannerKind { offline, stale, sessionExpired }

class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner.offline({
    this.message = "You're offline. Showing saved data.",
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert((actionLabel == null) == (onAction == null)),
       _kind = _AppStatusBannerKind.offline;

  const AppStatusBanner.stale({
    this.message = 'Saved data may be out of date.',
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert((actionLabel == null) == (onAction == null)),
       _kind = _AppStatusBannerKind.stale;

  const AppStatusBanner.sessionExpired({
    this.message = 'Your LEB2 session expired. Showing saved data.',
    this.actionLabel = 'Reconnect',
    required this.onAction,
    super.key,
  }) : _kind = _AppStatusBannerKind.sessionExpired;

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _AppStatusBannerKind _kind;

  @override
  Widget build(BuildContext context) {
    final statusColors = AppStatusColors.of(context);
    final (
      backgroundColor,
      foregroundColor,
      icon,
      semanticState,
    ) = switch (_kind) {
      _AppStatusBannerKind.offline => (
        statusColors.informationContainer,
        statusColors.onInformationContainer,
        Icons.cloud_off_outlined,
        'Offline',
      ),
      _AppStatusBannerKind.stale => (
        statusColors.staleContainer,
        statusColors.onStaleContainer,
        Icons.history_toggle_off_rounded,
        'Stale data',
      ),
      _AppStatusBannerKind.sessionExpired => (
        statusColors.warningContainer,
        statusColors.onWarningContainer,
        Icons.lock_clock_outlined,
        'Session expired',
      ),
    };

    return Semantics(
      key: const Key('app-status-banner-semantics'),
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: foregroundColor,
            width: AppBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: foregroundColor)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: '$semanticState: $message',
                      child: ExcludeSemantics(
                        child: Text(
                          message,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: foregroundColor),
                        ),
                      ),
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: foregroundColor,
                        ),
                        child: Text(actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
