// Hallmark · macrostructure: Workbench · theme: Cobalt
// Pre-emit critique: P5 H5 E5 S5 R5 V4

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/design_system/app_tokens.dart';
import '../../../core/security/credential_store.dart';
import '../application/session_setup_service.dart';

class SessionSetupPage extends StatefulWidget {
  const SessionSetupPage({
    required this.service,
    required this.onCompleted,
    super.key,
  });

  final SessionSetupService service;
  final FutureOr<void> Function() onCompleted;

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

class _SessionSetupPageState extends State<SessionSetupPage> {
  static const _maximumContentWidth = 1040.0;
  static const _maximumFormWidth = 520.0;
  static const _wideFormBreakpoint = 768.0;
  static const _maximumWideTextScale = 1.5;

  final _accessKeyController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _accessKeyFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  SavedSessionSummary? _savedSummary;
  SessionSetupCancellation? _cancellation;
  String? _accessKeyError;
  String? _usernameError;
  String? _passwordError;
  String? _status;
  bool _statusIsError = false;
  bool _busy = false;
  bool _summaryLoading = true;
  bool _showAccessKey = false;
  bool _showPassword = false;
  bool _automaticReauthentication = false;
  bool _navigationPending = false;
  int _operationId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedSummary());
  }

  Future<void> _loadSavedSummary() async {
    final summary = await widget.service.readSavedSessionSummary();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedSummary = summary;
      _summaryLoading = false;
    });
  }

  Future<void> _submit() async {
    if (_busy || _summaryLoading || _navigationPending) {
      return;
    }
    if (!_validateCredentials()) {
      return;
    }
    final accessKey = normalizeAccessKey(_accessKeyController.text)!;

    final operationId = ++_operationId;
    final cancellation = SessionSetupCancellation();
    setState(() {
      _busy = true;
      _cancellation = cancellation;
      _statusIsError = false;
      _status = 'Checking connection…';
    });

    final result = await widget.service.connectWithCredentials(
      accessKey: accessKey,
      username: _usernameController.text,
      password: _passwordController.text,
      enableAutomaticReauthentication: _automaticReauthentication,
      cancellation: cancellation,
    );
    await _handleResult(result, operationId);
  }

  Future<void> _verifySavedSession() async {
    if (_busy || _summaryLoading || _navigationPending) {
      return;
    }

    final operationId = ++_operationId;
    final cancellation = SessionSetupCancellation();
    setState(() {
      _busy = true;
      _cancellation = cancellation;
      _statusIsError = false;
      _status = 'Checking saved session…';
    });
    final result = await widget.service.verifySavedSession(
      cancellation: cancellation,
    );
    await _handleResult(result, operationId);
  }

  bool _validateCredentials() {
    setState(() {
      _accessKeyError = null;
      _usernameError = null;
      _passwordError = null;
      _status = null;
      _statusIsError = false;
    });

    if (!_validateAccessKey()) {
      return false;
    }
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _usernameError = 'Enter your LEB2 username.';
      });
      _usernameFocus.requestFocus();
      return false;
    }
    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _passwordError = 'Enter your LEB2 password.';
      });
      _passwordFocus.requestFocus();
      return false;
    }
    return true;
  }

  bool _validateAccessKey() {
    if (normalizeAccessKey(_accessKeyController.text) == null) {
      setState(() {
        _accessKeyError =
            'Enter the UUID access key from your backend operator.';
      });
      _accessKeyFocus.requestFocus();
      return false;
    }
    return true;
  }

  Future<void> _handleResult(SessionSetupResult result, int operationId) async {
    if (!mounted || operationId != _operationId) {
      return;
    }
    if (result is SessionSetupSuccess) {
      setState(() {
        _status = 'Session verified. Opening semester selection…';
        _statusIsError = false;
        _cancellation = null;
      });
      await _completeNavigation();
      return;
    }

    final failure = result as SessionSetupFailure;
    setState(() {
      _busy = false;
      _cancellation = null;
      _statusIsError = failure.kind != SessionSetupFailureKind.cancelled;
      _status = _failureMessage(failure);
    });
  }

  Future<void> _completeNavigation() async {
    try {
      await Future<void>.sync(widget.onCompleted);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _navigationPending = true;
        _statusIsError = true;
        _status =
            'Your session is saved, but semester selection could not open.';
      });
    }
  }

  Future<void> _retryNavigation() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'Opening semester selection…';
    });
    await _completeNavigation();
  }

  String _failureMessage(SessionSetupFailure failure) {
    return switch (failure.kind) {
      SessionSetupFailureKind.invalidInput =>
        'Check the highlighted fields and try again.',
      SessionSetupFailureKind.incompleteSavedSession =>
        'Setup incomplete. Sign in above to continue.',
      SessionSetupFailureKind.invalidOrExpiredSession =>
        'This session is expired or invalid. Sign in again.',
      SessionSetupFailureKind.invalidCredentials =>
        'The username or password was not accepted.',
      SessionSetupFailureKind.networkUnavailable =>
        'No network connection. Your saved session was not changed.',
      SessionSetupFailureKind.requestTimeout =>
        'The connection check took too long. Your saved session was not changed.',
      SessionSetupFailureKind.backendUnavailable =>
        'LEB2 could not be reached. Try again later.',
      SessionSetupFailureKind.rateLimited => _rateLimitMessage(
        failure.retryAfter,
      ),
      SessionSetupFailureKind.invalidResponse =>
        'Backend returned an unexpected response. Saved session unchanged.',
      SessionSetupFailureKind.secureStorageUnavailable =>
        'Secure credential storage is unavailable. No new session was saved.',
      SessionSetupFailureKind.localStorageUnavailable =>
        'Local session settings could not be saved.',
      SessionSetupFailureKind.differentAccountData =>
        'This device has data for another LEB2 account. Delete local data before connecting a different account.',
      SessionSetupFailureKind.accessKeyMissing ||
      SessionSetupFailureKind.accessKeyInvalid =>
        'This access key is missing or no longer valid. Enter a key provided by your backend operator.',
      SessionSetupFailureKind.accessKeyNotActivated =>
        'This access key has not been activated. Sign in with Username / password once to activate it.',
      SessionSetupFailureKind.accessKeyAccountMismatch =>
        'This access key cannot be used with this LEB2 account.',
      SessionSetupFailureKind.accessKeyReauthenticationRequired =>
        'Sign in with Username / password to finish initializing this access key.',
      SessionSetupFailureKind.accessKeyStoreUnavailable =>
        'Access-key verification is temporarily unavailable. Try again later.',
      SessionSetupFailureKind.deviceIdentityMissing =>
        'This device could not provide a valid device identifier.',
      SessionSetupFailureKind.deviceIdentityInvalid =>
        'This device could not provide a valid device identifier.',
      SessionSetupFailureKind.deviceNotBound =>
        'This access key needs to be connected to this device again. Sign in with your LEB2 username and password.',
      SessionSetupFailureKind.deviceMismatch =>
        'This access key is currently connected to another device. Log out on that device first, or ask your backend operator to reset the device binding.',
      SessionSetupFailureKind.clientVersionRequired ||
      SessionSetupFailureKind.clientVersionInvalid =>
        'This app could not provide a valid client version.',
      SessionSetupFailureKind.clientUpdateRequired =>
        'This version of LEB2 Watch is no longer compatible with the backend. Install the latest APK to continue.',
      SessionSetupFailureKind.persistenceUncertain =>
        'Saving could not be completed or safely restored. Review the saved-session status before trying again.',
      SessionSetupFailureKind.cancelled => 'Connection check cancelled.',
      SessionSetupFailureKind.busy => 'A connection check is already running.',
      SessionSetupFailureKind.unexpected =>
        'The connection could not be completed. Your saved session was not changed.',
    };
  }

  String _rateLimitMessage(Duration? retryAfter) {
    if (retryAfter == null) {
      return 'Too many checks are running. Try again later.';
    }
    final seconds = retryAfter.inSeconds;
    if (seconds < 60) {
      return 'Too many checks are running. Try again in ${seconds < 1 ? 1 : seconds} seconds.';
    }
    final minutes = (seconds / 60).ceil();
    return 'Too many checks are running. Try again in $minutes minutes.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useWideLayout =
                constraints.maxWidth >= _wideFormBreakpoint &&
                MediaQuery.textScalerOf(context).scale(1) <=
                    _maximumWideTextScale;
            return SingleChildScrollView(
              key: const Key('session-setup-scroll-view'),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _maximumContentWidth,
                  ),
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: useWideLayout
                        ? _wideLayout(context)
                        : _compactLayout(context),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _compactLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ConnectionIntroduction(),
        const SizedBox(height: AppSpacing.xl),
        _formPanel(context),
      ],
    );
  }

  Widget _wideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: _ConnectionIntroduction()),
        const SizedBox(width: AppSpacing.xl),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maximumFormWidth),
            child: _formPanel(context),
          ),
        ),
      ],
    );
  }

  Widget _formPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _accessKeyField(),
            const SizedBox(height: AppSpacing.md),
            _credentialFields(),
            const SizedBox(height: AppSpacing.lg),
            _statusRegion(context),
            if (_status != null) const SizedBox(height: AppSpacing.md),
            if (_navigationPending)
              FilledButton(
                key: const Key('session-navigation-retry'),
                onPressed: _busy ? null : _retryNavigation,
                child: const Text('Continue to semesters'),
              )
            else
              FilledButton(
                key: const Key('session-submit'),
                onPressed: _busy || _summaryLoading ? null : _submit,
                child: Text(_busy ? 'Checking…' : 'Verify and continue'),
              ),
            const SizedBox(height: AppSpacing.lg),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.lg),
            _savedSessionSection(context),
          ],
        ),
      ),
    );
  }

  Widget _accessKeyField() {
    return TextField(
      key: const Key('session-access-key-field'),
      controller: _accessKeyController,
      focusNode: _accessKeyFocus,
      enabled: !_busy && !_navigationPending,
      obscureText: !_showAccessKey,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Access key',
        helperText: 'Provided by your LEB2 Watch backend operator.',
        errorText: _accessKeyError,
        suffixIcon: _SecretVisibilityButton(
          visible: _showAccessKey,
          onPressed: _busy
              ? null
              : () => setState(() => _showAccessKey = !_showAccessKey),
        ),
      ),
    );
  }

  Widget _credentialFields() {
    return Column(
      key: const Key('credential-method-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('session-username-field'),
          controller: _usernameController,
          focusNode: _usernameFocus,
          enabled: !_busy && !_navigationPending,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Username',
            errorText: _usernameError,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('session-password-field'),
          controller: _passwordController,
          focusNode: _passwordFocus,
          enabled: !_busy && !_navigationPending,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          enableIMEPersonalizedLearning: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: _passwordError,
            suffixIcon: _SecretVisibilityButton(
              visible: _showPassword,
              onPressed: _busy
                  ? null
                  : () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile.adaptive(
          key: const Key('automatic-reauthentication-toggle'),
          contentPadding: EdgeInsets.zero,
          value: _automaticReauthentication,
          onChanged: _busy || _navigationPending
              ? null
              : (value) {
                  setState(() => _automaticReauthentication = value);
                },
          title: const Text('Save credentials for automatic reauthentication'),
          subtitle: const Text(
            'Off by default. Saves credentials only in OS secure storage.',
          ),
        ),
      ],
    );
  }

  Widget _statusRegion(BuildContext context) {
    if (_status == null && !_busy) {
      return const SizedBox.shrink(key: Key('session-status-empty'));
    }
    final color = _statusIsError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      key: const Key('session-status-live-region'),
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_busy) ...[
            const ExcludeSemantics(
              child: SizedBox.square(
                dimension: AppSpacing.lg,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              _status ?? 'Checking…',
              key: const Key('session-status-text'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedSessionSection(BuildContext context) {
    final summary = _savedSummary;
    if (_summaryLoading || summary == null) {
      return Semantics(
        liveRegion: true,
        child: const Text('Checking saved session…'),
      );
    }

    final title = switch (summary.state) {
      SavedSessionState.none => 'No saved session',
      SavedSessionState.ready => 'Saved session ready',
      SavedSessionState.incomplete => 'Setup incomplete',
      SavedSessionState.secureStorageUnavailable ||
      SavedSessionState.localStorageUnavailable =>
        'Saved-session status unavailable',
    };
    final detail = switch (summary.state) {
      SavedSessionState.none => 'Connect above to continue.',
      SavedSessionState.ready =>
        summary.automaticReauthenticationEnabled
            ? 'Automatic reauthentication is enabled.'
            : 'Automatic reauthentication is off.',
      SavedSessionState.incomplete => 'Sign in above to finish setup.',
      SavedSessionState.secureStorageUnavailable =>
        'Secure storage could not be read.',
      SavedSessionState.localStorageUnavailable =>
        'Local session settings could not be read.',
    };

    return Semantics(
      key: const Key('saved-session-summary'),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          if (summary.state == SavedSessionState.ready) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: const Key('verify-saved-session'),
              onPressed: _busy || _navigationPending
                  ? null
                  : _verifySavedSession,
              child: const Text('Verify saved session'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _accessKeyController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _accessKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _accessKeyFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }
}

class _ConnectionIntroduction extends StatelessWidget {
  const _ConnectionIntroduction();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LEB2 Watch',
          style: textTheme.titleLarge?.copyWith(
            color: colors.primary,
            fontWeight: AppTypography.headingWeight,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text('Connect LEB2', style: textTheme.headlineLarge),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'LEB2 Watch is not affiliated with KMUTT or LEB2. Username and '
          'password are sent only during sign-in or optional reauthentication.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
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
            'Access key and session cookie stay in OS secure storage. Protected '
            'requests send them with your LEB2 user ID. The ID stays in local '
            'SQLite.',
            style: textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _SecretVisibilityButton extends StatelessWidget {
  const _SecretVisibilityButton({
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final action = visible ? 'Hide' : 'Show';
    return IconButton(
      onPressed: onPressed,
      tooltip: '$action secret',
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
    );
  }
}
