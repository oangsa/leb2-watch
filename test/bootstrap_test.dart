import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/bootstrap.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/platform/desktop/desktop_pre_run_app_hook.dart';

void main() {
  testWidgets(
    'keeps desktop setup before the shell and mounts one ready graph',
    (tester) async {
      final hook = _BlockingDesktopHook();
      final storage = LocalDatabaseStorage();
      final credentials = _CredentialStore();
      final resolver = _BlockingStartupResolver();
      final configuration = AppConfiguration.parse();
      final flutterApplicationRunner = runApp;
      var applicationAttachments = 0;

      final bootstrapping = bootstrap(
        desktopPreRunAppHook: hook,
        applicationRunner: (application) {
          applicationAttachments += 1;
          flutterApplicationRunner(application);
        },
        configurationLoader: () => configuration,
        databaseStorage: storage,
        credentialStore: credentials,
        startupFlowResolver: resolver.call,
      );
      await tester.pump();

      expect(hook.initializeCalls, 1);
      expect(applicationAttachments, 0);
      expect(resolver.calls, 0);
      expect(find.text('Starting LEB2 Watch…'), findsNothing);
      expect(find.byType(Leb2WatchApp), findsNothing);

      hook.release.complete();
      await bootstrapping;
      await tester.pump();
      await resolver.started.future;

      expect(applicationAttachments, 1);
      expect(resolver.calls, 1);
      expect(resolver.databaseStorage, same(storage));
      expect(resolver.credentialStore, same(credentials));
      expect(find.text('Starting LEB2 Watch…'), findsOneWidget);
      expect(find.byType(Leb2WatchApp), findsNothing);

      resolver.release.complete(AppFlowStage.authentication);
      await tester.pump();

      expect(find.text('Starting LEB2 Watch…'), findsNothing);
      expect(find.byType(ProviderScope), findsOneWidget);
      expect(find.byType(Leb2WatchApp), findsOneWidget);
      final providerScope = tester.widget<ProviderScope>(
        find.byType(ProviderScope),
      );
      final app = tester.widget<Leb2WatchApp>(find.byType(Leb2WatchApp));
      expect(app.configuration, same(configuration));
      final appContext = tester.element(find.byType(Leb2WatchApp));
      final container = ProviderScope.containerOf(appContext, listen: false);
      expect(container.read(localDatabaseStorageProvider), same(storage));
      expect(container.read(credentialStoreProvider), same(credentials));
      expect(
        container.read(appFlowControllerProvider).stage,
        AppFlowStage.authentication,
      );

      await tester.pump();
      expect(
        tester.widget<ProviderScope>(find.byType(ProviderScope)),
        same(providerScope),
      );
      expect(resolver.calls, 1);
      expect(applicationAttachments, 1);

      await _removeApp(tester);
    },
  );

  testWidgets('shows a fixed failure after desktop preparation throws', (
    tester,
  ) async {
    var configurationLoads = 0;
    var resolverCalls = 0;

    await bootstrap(
      desktopPreRunAppHook: _ThrowingDesktopHook(
        StateError('sensitive native detail'),
      ),
      configurationLoader: () {
        configurationLoads += 1;
        return AppConfiguration.parse();
      },
      databaseStorage: LocalDatabaseStorage(),
      credentialStore: _CredentialStore(),
      startupFlowResolver:
          ({required databaseStorage, required credentialStore}) async {
            resolverCalls += 1;
            return AppFlowStage.ready;
          },
    );
    await tester.pump();

    expect(
      find.text(
        'LEB2 Watch could not finish starting. Saved data was not deleted.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive native detail'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('stack'), findsNothing);
    expect(find.byType(Leb2WatchApp), findsNothing);
    expect(configurationLoads, 0);
    expect(resolverCalls, 0);
    expect(tester.takeException(), isNull);

    await _removeApp(tester);
  });

  testWidgets('shows fixed invalid-configuration copy without local startup', (
    tester,
  ) async {
    var resolverCalls = 0;

    await bootstrap(
      desktopPreRunAppHook: const NoOpDesktopPreRunAppHook(),
      configurationLoader: () {
        throw const FormatException(
          'Unsupported APP_ENV value: private-staging',
        );
      },
      databaseStorage: LocalDatabaseStorage(),
      credentialStore: _CredentialStore(),
      startupFlowResolver:
          ({required databaseStorage, required credentialStore}) async {
            resolverCalls += 1;
            return AppFlowStage.ready;
          },
    );
    await tester.pump();

    expect(
      find.text(
        'This build has an invalid application configuration. '
        'Rebuild it with a supported APP_ENV value.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private-staging'), findsNothing);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Leb2WatchApp), findsNothing);
    expect(resolverCalls, 0);
    expect(tester.takeException(), isNull);

    await _removeApp(tester);
  });

  testWidgets('shows fixed local-data copy after local startup throws', (
    tester,
  ) async {
    await bootstrap(
      desktopPreRunAppHook: const NoOpDesktopPreRunAppHook(),
      configurationLoader: AppConfiguration.fromEnvironment,
      databaseStorage: LocalDatabaseStorage(),
      credentialStore: _CredentialStore(),
      startupFlowResolver:
          ({required databaseStorage, required credentialStore}) {
            throw StateError(
              'credential=<SESSION_COOKIE>; '
              'path=/private/user/leb2_watch.sqlite',
            );
          },
    );
    await tester.pump();

    expect(
      find.text(
        'LEB2 Watch could not open its local data. Saved data was not deleted.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('<SESSION_COOKIE>'), findsNothing);
    expect(find.textContaining('/private/user'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Leb2WatchApp), findsNothing);
    expect(tester.takeException(), isNull);

    await _removeApp(tester);
  });

  testWidgets('ignores a startup completion after the shell is disposed', (
    tester,
  ) async {
    final resolver = _BlockingStartupResolver();

    await bootstrap(
      desktopPreRunAppHook: const NoOpDesktopPreRunAppHook(),
      configurationLoader: AppConfiguration.fromEnvironment,
      databaseStorage: LocalDatabaseStorage(),
      credentialStore: _CredentialStore(),
      startupFlowResolver: resolver.call,
    );
    await tester.pump();
    await resolver.started.future;

    expect(find.text('Starting LEB2 Watch…'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    resolver.release.complete(AppFlowStage.ready);
    await tester.pump();

    expect(find.byType(Leb2WatchApp), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'failure shell supports narrow 2x text in ${brightness.name} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await bootstrap(
          desktopPreRunAppHook: const NoOpDesktopPreRunAppHook(),
          configurationLoader: () {
            throw const FormatException('raw private value');
          },
        );
        await tester.pump();

        final status = find.byKey(const Key('bootstrap-failure-status'));
        expect(status, findsOneWidget);
        expect(
          tester.getSemantics(status).label,
          contains('LEB2 Watch startup failed'),
        );
        expect(Theme.of(tester.element(status)).brightness, brightness);
        expect(tester.takeException(), isNull);

        await _removeApp(tester);
      },
    );
  }
}

Future<void> _removeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

final class _BlockingDesktopHook implements DesktopPreRunAppHook {
  final Completer<void> release = Completer<void>();
  int initializeCalls = 0;

  @override
  Future<void> initialize() {
    initializeCalls += 1;
    return release.future;
  }
}

final class _ThrowingDesktopHook implements DesktopPreRunAppHook {
  const _ThrowingDesktopHook(this.error);

  final Object error;

  @override
  Future<void> initialize() async {
    throw error;
  }
}

final class _BlockingStartupResolver {
  final Completer<void> started = Completer<void>();
  final Completer<AppFlowStage> release = Completer<AppFlowStage>();
  int calls = 0;
  LocalDatabaseStorage? databaseStorage;
  CredentialStore? credentialStore;

  Future<AppFlowStage> call({
    required LocalDatabaseStorage databaseStorage,
    required CredentialStore credentialStore,
  }) {
    calls += 1;
    this.databaseStorage = databaseStorage;
    this.credentialStore = credentialStore;
    started.complete();
    return release.future;
  }
}

final class _CredentialStore implements CredentialStore {
  @override
  Future<String?> readAccessKey() async => null;

  @override
  Future<void> saveAccessKey(String value) async {}

  @override
  Future<void> deleteAccessKey() async {}

  @override
  Future<String?> readSessionCookie() async => null;

  @override
  Future<void> saveSessionCookie(String value) async {}

  @override
  Future<void> deleteSessionCookie() async {}

  @override
  Future<StoredCredentials?> readCredentials() async => null;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {}

  @override
  Future<void> deleteCredentials() async {}

  @override
  Future<void> clear() async {}
}
