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
        const SizedBox(height: AppSpacing.sm),
        for (final (index, paragraph) in step.paragraphs.indexed) ...[
          Text(paragraph, style: textTheme.bodyLarge),
          if (index != step.paragraphs.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
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
      child: Text(isFinalStep ? 'Sign in' : 'Next'),
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
  });

  final String title;
  final IconData icon;
  final List<String> paragraphs;
}

const _steps = <_OnboardingStep>[
  _OnboardingStep(
    title: 'Your assignments, in one place',
    icon: Icons.assignment_outlined,
    paragraphs: [
      'LEB2 Watch keeps a local view of your courses, assignments, deadlines, '
          'and submission status.',
      'It is independent and is not affiliated with or endorsed by KMUTT or '
          'LEB2.',
    ],
  ),
  _OnboardingStep(
    title: 'Stored on this device',
    icon: Icons.shield_outlined,
    paragraphs: [
      'Assignments, settings, and notification state live in a local '
          'database.',
      'Your session cookie stays in OS secure storage. Username and password '
          'are saved only when you choose to stay signed in.',
    ],
  ),
  _OnboardingStep(
    title: 'What the backend receives',
    icon: Icons.sync_alt_outlined,
    paragraphs: [
      'Checks send your session cookie and LEB2 user ID. Username and password '
          'are sent only when signing in.',
      'The backend stores neither. It keeps short-lived request fingerprints '
          'and cached results in memory.',
    ],
  ),
  _OnboardingStep(
    title: 'Notifications are optional',
    icon: Icons.notifications_none_outlined,
    paragraphs: [
      'Alerts and reminders are created on this device.',
      'You can keep notifications off and still read saved data or refresh by '
          'hand.',
    ],
  ),
  _OnboardingStep(
    title: 'Background checks are best effort',
    icon: Icons.schedule_outlined,
    paragraphs: [
      'Android battery controls and iOS scheduling can delay checks. Desktop '
          'checks pause when the app is not running.',
      'Exact timing is never guaranteed. Opening the app always refreshes.',
    ],
  ),
];
