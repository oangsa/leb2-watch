import 'package:flutter/material.dart';

import '../../../app/design_system/app_breakpoints.dart';
import '../../../app/design_system/app_tokens.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const _maximumReadingWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('privacy-page'),
      appBar: AppBar(title: const Text('Privacy')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = AppBreakpoints.classify(constraints.maxWidth);
            final horizontalPadding = switch (windowClass) {
              AppWindowClass.compact => AppSpacing.md,
              AppWindowClass.medium => AppSpacing.lg,
              AppWindowClass.expanded => AppSpacing.xl,
            };

            return SingleChildScrollView(
              key: const Key('privacy-scroll-view'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.lg,
                horizontalPadding,
                AppSpacing.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _maximumReadingWidth,
                  ),
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PageHeading(),
                        SizedBox(height: AppSpacing.lg),
                        _ThirdPartyDisclaimer(),
                        SizedBox(height: AppSpacing.lg),
                        _PrivacySection(
                          headingKey: Key('privacy-local-storage-heading'),
                          title: 'Stored on this device',
                          icon: Icons.shield_outlined,
                          paragraphs: [
                            'Assignment snapshots, settings, and notification '
                                'state stay in a local SQLite database on this '
                                'device.',
                            'Your LEB2 session cookie is stored in '
                                'operating-system protected storage. Your '
                                'username and password are stored there only '
                                'if you enable automatic reauthentication.',
                            'Credentials are not stored in SQLite, plaintext '
                                'files, logs, or notifications.',
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),
                        _PrivacySection(
                          headingKey: Key('privacy-backend-heading'),
                          title: 'What each backend request receives',
                          icon: Icons.sync_alt_outlined,
                          paragraphs: [
                            'The credentials needed for a backend request are '
                                'sent temporarily with that request. Protected '
                                'checks send your session cookie and numeric '
                                'LEB2 user ID. Your username and password are '
                                'sent only when signing in or automatically '
                                'reauthenticating.',
                            'The backend does not durably store credentials or '
                                'assignments. It may keep short-lived request '
                                'fingerprints and cached results in process '
                                'memory.',
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),
                        _PrivacySection(
                          headingKey: Key('privacy-notifications-heading'),
                          title: 'Notifications are local and optional',
                          icon: Icons.notifications_none_outlined,
                          paragraphs: [
                            'New-assignment alerts and deadline reminders are '
                                'created on this device.',
                            'Notification permission is requested only after '
                                'you choose that action. You can still view '
                                'saved data and refresh manually when '
                                'notifications are off.',
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),
                        _PrivacySection(
                          headingKey: Key('privacy-background-heading'),
                          title: 'Background checks are best effort',
                          icon: Icons.schedule_outlined,
                          paragraphs: [
                            'Android may delay periodic checks because of '
                                'network constraints, battery optimization, or '
                                'Doze.',
                            'On iPhone and iPad, iOS decides when background '
                                'refresh runs. A check may be delayed for hours '
                                'or may not run until you reopen the app.',
                            'On desktop, monitoring requires the app to keep '
                                'running in the background. Sleep, logout, or '
                                'quitting pauses checks.',
                            'LEB2 Watch cannot promise exact check times or '
                                'exact notification delivery. Opening or '
                                'resuming the app provides another opportunity '
                                'to refresh.',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('privacy-page-heading'),
      header: true,
      child: Text(
        'Privacy and local data',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
    );
  }
}

class _ThirdPartyDisclaimer extends StatelessWidget {
  const _ThirdPartyDisclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: const Key('privacy-third-party-disclaimer'),
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadii.prominent),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'LEB2 Watch is an independent third-party application and is not '
            'affiliated with or endorsed by KMUTT or LEB2.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: AppTypography.headingWeight,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.headingKey,
    required this.title,
    required this.icon,
    required this.paragraphs,
  });

  final Key headingKey;
  final String title;
  final IconData icon;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: AppElevation.flat,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: AppSizing.stateIcon,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              key: headingKey,
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (index, paragraph) in paragraphs.indexed) ...[
              Text(paragraph, style: theme.textTheme.bodyLarge),
              if (index != paragraphs.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
