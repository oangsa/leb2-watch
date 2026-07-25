// Hallmark · macrostructure: Long Document · theme: Cobalt
// Pre-emit critique: P5 H5 E5 S5 R5 V4

import 'package:flutter/material.dart';

import '../../../app/design_system/app_breakpoints.dart';
import '../../../app/design_system/app_tokens.dart';

class PrivacyOnboardingPage extends StatefulWidget {
  const PrivacyOnboardingPage({required this.onCompleted, super.key});

  final VoidCallback onCompleted;

  @override
  State<PrivacyOnboardingPage> createState() => _PrivacyOnboardingPageState();
}

class _PrivacyOnboardingPageState extends State<PrivacyOnboardingPage> {
  static const _maximumContentWidth = 1040.0;
  static const _maximumReadingWidth = 640.0;
  static const _railWidth = 248.0;
  static const _maximumRailTextScale = 1.5;

  var _currentStep = 0;
  var _didComplete = false;

  _OnboardingStep get _step => _steps[_currentStep];

  void _goBack() {
    if (_currentStep == 0) {
      return;
    }
    setState(() => _currentStep -= 1);
  }

  void _advance() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep += 1);
      return;
    }
    if (_didComplete) {
      return;
    }

    setState(() => _didComplete = true);
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useRail =
                constraints.maxWidth >= AppBreakpoints.medium &&
                MediaQuery.textScalerOf(context).scale(1) <=
                    _maximumRailTextScale;

            return SingleChildScrollView(
              key: const Key('onboarding-scroll-view'),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _maximumContentWidth,
                  ),
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: useRail ? _buildRailLayout() : _buildCompactLayout(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompactLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProductMark(),
        const SizedBox(height: AppSpacing.xl),
        _Progress(stepIndex: _currentStep, stepCount: _steps.length),
        const SizedBox(height: AppSpacing.xl),
        _StepContent(step: _step, stepIndex: _currentStep),
        const SizedBox(height: AppSpacing.xl),
        _Actions(
          canGoBack: _currentStep > 0,
          isFinalStep: _currentStep == _steps.length - 1,
          completionPending: _didComplete,
          stacked: true,
          onBack: _goBack,
          onAdvance: _advance,
        ),
      ],
    );
  }

  Widget _buildRailLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _railWidth,
          child: _OnboardingRail(currentStep: _currentStep, steps: _steps),
        ),
        const SizedBox(width: AppSpacing.xl),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: AppBorders.hairline,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _maximumReadingWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepContent(step: _step, stepIndex: _currentStep),
                    const SizedBox(height: AppSpacing.xl),
                    _Actions(
                      canGoBack: _currentStep > 0,
                      isFinalStep: _currentStep == _steps.length - 1,
                      completionPending: _didComplete,
                      stacked: false,
                      onBack: _goBack,
                      onAdvance: _advance,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductMark extends StatelessWidget {
  const _ProductMark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'LEB2 Watch',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: AppTypography.headingWeight,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.stepIndex, required this.stepCount});

  final int stepIndex;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final visibleValue = 'Step ${stepIndex + 1} of $stepCount';

    return Semantics(
      key: const Key('onboarding-progress-semantics'),
      label: 'Onboarding progress',
      value: visibleValue,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              visibleValue,
              key: const Key('onboarding-progress-label'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(
              value: (stepIndex + 1) / stepCount,
              minHeight: AppBorders.hairline * 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingRail extends StatelessWidget {
  const _OnboardingRail({required this.currentStep, required this.steps});

  final int currentStep;
  final List<_OnboardingStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProductMark(),
        const SizedBox(height: AppSpacing.xl),
        _Progress(stepIndex: currentStep, stepCount: steps.length),
        const SizedBox(height: AppSpacing.xl),
        ExcludeSemantics(
          child: Column(
            children: [
              for (final (index, step) in steps.indexed) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: AppSpacing.lg,
                      child: Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: index == currentStep
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        step.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: index == currentStep
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontWeight: index == currentStep
                              ? AppTypography.labelWeight
                              : AppTypography.bodyWeight,
                        ),
                      ),
                    ),
                  ],
                ),
                if (index != steps.length - 1)
                  const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({required this.step, required this.stepIndex});

  final _OnboardingStep step;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            step.icon,
            key: const Key('onboarding-step-icon'),
            size: AppSizing.stateIcon,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          key: const Key('onboarding-current-heading-semantics'),
          header: true,
          child: Text(
            step.title,
            key: Key('onboarding-step-title-$stepIndex'),
            style: textTheme.headlineLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final paragraph in step.paragraphs) ...[
          Text(paragraph, style: textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.md),
        ],
        if (step.callout != null)
          Container(
            key: const Key('onboarding-callout'),
            padding: const EdgeInsets.only(left: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colors.primary,
                  width: AppBorders.hairline * 3,
                ),
              ),
            ),
            child: Text(
              step.callout!,
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: AppTypography.labelWeight,
              ),
            ),
          ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.canGoBack,
    required this.isFinalStep,
    required this.completionPending,
    required this.stacked,
    required this.onBack,
    required this.onAdvance,
  });

  final bool canGoBack;
  final bool isFinalStep;
  final bool completionPending;
  final bool stacked;
  final VoidCallback onBack;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final backButton = OutlinedButton(
      key: const Key('onboarding-back-button'),
      onPressed: onBack,
      child: const Text('Back'),
    );
    final primaryButton = FilledButton(
      key: const Key('onboarding-primary-button'),
      onPressed: completionPending ? null : onAdvance,
      child: Text(isFinalStep ? 'Continue to sign in' : 'Next'),
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canGoBack) ...[backButton, const SizedBox(height: AppSpacing.sm)],
          primaryButton,
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [if (canGoBack) backButton, primaryButton],
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.title,
    required this.icon,
    required this.paragraphs,
    this.callout,
  });

  final String title;
  final IconData icon;
  final List<String> paragraphs;
  final String? callout;
}

const _steps = <_OnboardingStep>[
  _OnboardingStep(
    title: 'Assignments, ready when you are',
    icon: Icons.assignment_outlined,
    paragraphs: [
      'LEB2 Watch shows saved assignment data immediately, then checks for '
          'updates asynchronously.',
    ],
    callout:
        'LEB2 Watch is an independent third-party application and is not '
        'affiliated with or endorsed by KMUTT or LEB2.',
  ),
  _OnboardingStep(
    title: 'Stored locally, protected separately',
    icon: Icons.shield_outlined,
    paragraphs: [
      'Assignment snapshots, settings, and notification state stay in a local '
          'SQLite database on this device.',
      'Your LEB2 session cookie is stored in operating-system protected '
          'storage. Your username and password are stored there only if you '
          'later enable automatic reauthentication.',
      'Credentials are not stored in SQLite, plaintext files, logs, or '
          'notifications.',
    ],
  ),
  _OnboardingStep(
    title: 'What each backend request receives',
    icon: Icons.sync_alt_outlined,
    paragraphs: [
      'The credentials needed for a backend request are sent temporarily with '
          'that request. Protected checks send your session cookie and numeric '
          'LEB2 user ID. Your username and password are sent only when signing '
          'in or automatically reauthenticating.',
      'The backend does not durably store credentials or assignments. It may '
          'keep short-lived request fingerprints and cached results in process '
          'memory.',
    ],
  ),
  _OnboardingStep(
    title: 'Notifications are your choice',
    icon: Icons.notifications_none_outlined,
    paragraphs: [
      'New-assignment alerts and deadline reminders are created on this '
          'device.',
      'You will choose whether to allow notifications later. Continuing here '
          'does not open a system permission prompt, and you can still view '
          'saved data and refresh manually if notifications are off.',
    ],
  ),
  _OnboardingStep(
    title: 'Background checks are best effort',
    icon: Icons.schedule_outlined,
    paragraphs: [
      'Android may delay periodic checks because of network constraints, '
          'battery optimization, or Doze.',
      'On iPhone and iPad, iOS decides when background refresh runs. A check '
          'may be delayed for hours or may not run until you reopen the app.',
      'On desktop, monitoring requires the app to keep running in the '
          'background. Sleep, logout, or quitting pauses checks.',
      'LEB2 Watch cannot promise exact check times or exact notification '
          'delivery. Opening or resuming the app provides another opportunity '
          'to refresh.',
    ],
  ),
];
