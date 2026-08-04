import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app_dependencies.dart';
import 'src/app/leb2_watch_app.dart';
import 'src/app/routing/app_flow.dart';
import 'src/app/startup/app_startup_flow.dart';
import 'src/core/config/app_configuration.dart';
import 'src/core/database/local_database_storage.dart';
import 'src/core/security/credential_store.dart';
import 'src/core/security/flutter_secure_credential_store.dart';
import 'src/platform/desktop/autostart/desktop_autostart_factory.dart';
import 'src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'src/platform/desktop/desktop_pre_run_app_hook.dart';

typedef AppConfigurationLoader = AppConfiguration Function();

// The bootstrap shell is dependency-free; ProviderScope is attached only
// after the startup attempt succeeds.
typedef ApplicationRunner = void Function(Widget application);

typedef AppStartupFlowResolver =
    Future<AppFlowStage> Function({
      required LocalDatabaseStorage databaseStorage,
      required CredentialStore credentialStore,
    });

Future<void> bootstrap({
  DesktopPreRunAppHook? desktopPreRunAppHook,
  ApplicationRunner applicationRunner = runApp,
  AppConfigurationLoader configurationLoader = AppConfiguration.fromEnvironment,
  LocalDatabaseStorage? databaseStorage,
  CredentialStore? credentialStore,
  AppStartupFlowResolver? startupFlowResolver,
  Duration localDataRetryDelay = _localDataOpenRetryDelay,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await (desktopPreRunAppHook ?? createDesktopPreRunAppHook()).initialize();
  } on Object {
    applicationRunner(
      const _BootstrapRecoveryShell.failed(
        _BootstrapFailure.startupIntegrationUnavailable,
      ),
    );
    return;
  }

  applicationRunner(
    _BootstrapRecoveryShell.loading(
      startupAttempt: () => _prepareApplication(
        configurationLoader: configurationLoader,
        databaseStorage: databaseStorage,
        credentialStore: credentialStore,
        startupFlowResolver: startupFlowResolver,
        localDataRetryDelay: localDataRetryDelay,
      ),
    ),
  );
}

Future<_BootstrapAttemptResult> _prepareApplication({
  required AppConfigurationLoader configurationLoader,
  required LocalDatabaseStorage? databaseStorage,
  required CredentialStore? credentialStore,
  required AppStartupFlowResolver? startupFlowResolver,
  required Duration localDataRetryDelay,
}) async {
  late final AppConfiguration configuration;
  try {
    configuration = configurationLoader();
  } on FormatException {
    return const _BootstrapAttemptFailure(
      _BootstrapFailure.invalidConfiguration,
    );
  } on Object {
    return const _BootstrapAttemptFailure(
      _BootstrapFailure.startupIntegrationUnavailable,
    );
  }

  late final LocalDatabaseStorage resolvedDatabaseStorage;
  late final CredentialStore resolvedCredentialStore;
  try {
    resolvedDatabaseStorage = databaseStorage ?? LocalDatabaseStorage();
    resolvedCredentialStore = credentialStore ?? FlutterSecureCredentialStore();
  } on Object {
    return const _BootstrapAttemptFailure(
      _BootstrapFailure.startupIntegrationUnavailable,
    );
  }

  // Background sync runs in its own isolate, so a startup open can lose a
  // short race for the same database. One retry converts that transient
  // contention into a normal start instead of a dead-end failure screen.
  for (var attempt = 0; attempt < _localDataOpenAttempts; attempt += 1) {
    try {
      final initialStage =
          await (startupFlowResolver ?? resolveInitialAppFlowStage)(
            databaseStorage: resolvedDatabaseStorage,
            credentialStore: resolvedCredentialStore,
          );
      return _BootstrapAttemptSuccess(
        configuration: configuration,
        databaseStorage: resolvedDatabaseStorage,
        credentialStore: resolvedCredentialStore,
        initialStage: initialStage,
      );
    } on Object {
      if (attempt == _localDataOpenAttempts - 1) {
        return const _BootstrapAttemptFailure(
          _BootstrapFailure.localDataUnavailable,
        );
      }
      if (localDataRetryDelay > Duration.zero) {
        await Future<void>.delayed(localDataRetryDelay);
      }
    }
  }
  return const _BootstrapAttemptFailure(_BootstrapFailure.localDataUnavailable);
}

const _localDataOpenAttempts = 3;
const _localDataOpenRetryDelay = Duration(milliseconds: 250);

final class _BootstrapRecoveryShell extends StatefulWidget {
  const _BootstrapRecoveryShell.loading({required this.startupAttempt})
    : initialFailure = null;

  const _BootstrapRecoveryShell.failed(this.initialFailure)
    : startupAttempt = null;

  final Future<_BootstrapAttemptResult> Function()? startupAttempt;
  final _BootstrapFailure? initialFailure;

  @override
  State<_BootstrapRecoveryShell> createState() =>
      _BootstrapRecoveryShellState();
}

final class _BootstrapRecoveryShellState
    extends State<_BootstrapRecoveryShell> {
  _BootstrapFailure? _failure;
  Object? _activeAttempt;
  bool _attemptStarted = false;
  Widget? _readyChild;

  @override
  void initState() {
    super.initState();
    _failure = widget.initialFailure;
    if (_failure == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startAttempt());
        }
      });
    }
  }

  void _retryAttempt() {
    if (widget.startupAttempt == null) {
      return;
    }
    _attemptStarted = false;
    setState(() => _failure = null);
    unawaited(_startAttempt());
  }

  Future<void> _startAttempt() async {
    if (_attemptStarted || widget.startupAttempt == null) {
      return;
    }
    _attemptStarted = true;
    final attempt = Object();
    _activeAttempt = attempt;

    final result = await widget.startupAttempt!();
    if (!mounted || !identical(_activeAttempt, attempt)) {
      return;
    }

    switch (result) {
      case _BootstrapAttemptSuccess():
        final readyChild = _buildReadyApplication(result);
        setState(() {
          _activeAttempt = null;
          _readyChild = readyChild;
        });
      case _BootstrapAttemptFailure():
        setState(() {
          _activeAttempt = null;
          _failure = result.failure;
        });
    }
  }

  @override
  void dispose() {
    _activeAttempt = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readyChild = _readyChild;
    if (readyChild != null) {
      return readyChild;
    }

    return MaterialApp(
      title: 'LEB2 Watch',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: _BootstrapStatusPage(
        failure: _failure,
        onRetry: widget.startupAttempt == null ? null : _retryAttempt,
      ),
    );
  }
}

Widget _buildReadyApplication(_BootstrapAttemptSuccess result) {
  return ProviderScope(
    overrides: [
      appConfigurationProvider.overrideWithValue(result.configuration),
      localDatabaseStorageProvider.overrideWithValue(result.databaseStorage),
      credentialStoreProvider.overrideWithValue(result.credentialStore),
      initialAppFlowStageProvider.overrideWithValue(result.initialStage),
      desktopAutostartServiceProvider.overrideWith((ref) {
        final service = createDesktopAutostartService();
        if (service is LocalDesktopAutostartService) {
          ref.onDispose(service.dispose);
        }
        return service;
      }),
    ],
    child: Leb2WatchApp(configuration: result.configuration),
  );
}

final class _BootstrapStatusPage extends StatelessWidget {
  const _BootstrapStatusPage({required this.failure, this.onRetry});

  final _BootstrapFailure? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = this.failure;
    final isLoading = failure == null;
    final message = switch (failure) {
      null => 'Starting…',
      _BootstrapFailure.invalidConfiguration =>
        'This build has an invalid configuration. Rebuild it with a '
            'supported APP_ENV value.',
      _BootstrapFailure.localDataUnavailable =>
        'Could not open local data. Nothing was deleted.',
      _BootstrapFailure.startupIntegrationUnavailable =>
        'Could not finish starting. Nothing was deleted.',
    };
    final semanticsLabel = isLoading
        ? 'LEB2 Watch is starting'
        : 'LEB2 Watch startup failed. $message';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                key: isLoading
                    ? const Key('bootstrap-loading-status')
                    : const Key('bootstrap-failure-status'),
                container: true,
                liveRegion: true,
                label: semanticsLabel,
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BootstrapStatusIndicator(isLoading: isLoading),
                    const SizedBox(height: 24),
                    Text(
                      'LEB2 Watch',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (!isLoading &&
                        failure != _BootstrapFailure.invalidConfiguration &&
                        onRetry != null) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('bootstrap-retry-button'),
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _BootstrapStatusIndicator extends StatelessWidget {
  const _BootstrapStatusIndicator({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return Icon(
        Icons.error_outline,
        size: 40,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (MediaQuery.of(context).disableAnimations) {
      return const Icon(Icons.hourglass_top, size: 40);
    }
    return const SizedBox.square(
      dimension: 40,
      child: CircularProgressIndicator(),
    );
  }
}

sealed class _BootstrapAttemptResult {
  const _BootstrapAttemptResult();
}

final class _BootstrapAttemptSuccess extends _BootstrapAttemptResult {
  const _BootstrapAttemptSuccess({
    required this.configuration,
    required this.databaseStorage,
    required this.credentialStore,
    required this.initialStage,
  });

  final AppConfiguration configuration;
  final LocalDatabaseStorage databaseStorage;
  final CredentialStore credentialStore;
  final AppFlowStage initialStage;
}

final class _BootstrapAttemptFailure extends _BootstrapAttemptResult {
  const _BootstrapAttemptFailure(this.failure);

  final _BootstrapFailure failure;
}

enum _BootstrapFailure {
  invalidConfiguration,
  localDataUnavailable,
  startupIntegrationUnavailable,
}
