import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/bootstrap.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/platform/desktop/desktop_pre_run_app_hook.dart';

void main() {
  testWidgets('awaits desktop setup and resolved flow before attaching', (
    tester,
  ) async {
    final hook = _BlockingDesktopHook();
    final storage = LocalDatabaseStorage();
    final credentials = _CredentialStore();
    final resolver = _BlockingStartupResolver();

    final bootstrapping = bootstrap(
      desktopPreRunAppHook: hook,
      databaseStorage: storage,
      credentialStore: credentials,
      startupFlowResolver: resolver.call,
    );
    await tester.pump();

    expect(hook.initializeCalls, 1);
    expect(resolver.calls, 0);
    expect(find.byType(Leb2WatchApp), findsNothing);

    hook.release.complete();
    await resolver.started.future;
    await tester.pump();

    expect(resolver.calls, 1);
    expect(resolver.databaseStorage, same(storage));
    expect(resolver.credentialStore, same(credentials));
    expect(find.byType(Leb2WatchApp), findsNothing);

    resolver.release.complete(AppFlowStage.authentication);
    await bootstrapping;
    await tester.pump();

    expect(find.byType(Leb2WatchApp), findsOneWidget);
    final appContext = tester.element(find.byType(Leb2WatchApp));
    expect(
      ProviderScope.containerOf(
        appContext,
        listen: false,
      ).read(appFlowControllerProvider).stage,
      AppFlowStage.authentication,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
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
