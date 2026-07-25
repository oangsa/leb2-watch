import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_configuration.dart';
import '../core/database/app_database.dart';
import '../core/database/local_database_storage.dart';
import '../core/network/backend_api_client.dart';
import '../core/security/credential_store.dart';
import '../core/security/flutter_secure_credential_store.dart';
import '../core/session/session_lifecycle.dart';
import '../features/assignments/sync/assignment_sync_service.dart';
import '../features/assignments/sync/local_assignment_sync_service.dart';
import '../features/authentication/application/session_setup_service.dart';
import '../features/authentication/data/session_identity_store.dart';

final appConfigurationProvider = Provider<AppConfiguration>((ref) {
  throw StateError('AppConfiguration was not provided.');
});

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  return FlutterSecureCredentialStore();
});

final localDatabaseStorageProvider = Provider<LocalDatabaseStorage>((ref) {
  return LocalDatabaseStorage();
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final storage = ref.watch(localDatabaseStorageProvider);
  AppDatabase? database;
  var disposed = false;

  ref.onDispose(() {
    disposed = true;
    final openedDatabase = database;
    if (openedDatabase != null) {
      unawaited(_closeDatabase(openedDatabase));
    }
  });

  final openedDatabase = await storage.openDatabase();
  database = openedDatabase;
  if (disposed) {
    await _closeDatabase(openedDatabase);
  }
  return openedDatabase;
});

Future<void> _closeDatabase(AppDatabase database) async {
  try {
    await database.close();
  } on Object {
    // Provider teardown has no safe consumer for a close failure.
  }
}

final backendTransportClientProvider = Provider<DioBackendApiClient>((ref) {
  return DioBackendApiClient(
    configuration: ref.watch(appConfigurationProvider),
    credentialStore: ref.watch(credentialStoreProvider),
  );
});

final backendApiClientProvider = Provider<BackendApiClient>((ref) {
  return ref.watch(backendTransportClientProvider);
});

final backendSessionClientProvider = Provider<BackendSessionClient>((ref) {
  return ref.watch(backendTransportClientProvider);
});

final sessionIdentityStoreProvider = FutureProvider<SessionIdentityStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftSessionIdentityStore(database);
});

final sessionLifecycleStoreProvider = FutureProvider<SessionLifecycleStore>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return DriftSessionLifecycleStore(database);
});

final sessionLifecycleProvider = StreamProvider<SessionLifecycleSnapshot>((
  ref,
) async* {
  final store = await ref.watch(sessionLifecycleStoreProvider.future);
  yield* store.watch();
});

final assignmentSyncServiceProvider = FutureProvider<AssignmentSyncService>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return LocalAssignmentSyncService(
    apiClient: ref.watch(backendApiClientProvider),
    database: database,
  );
});

final sessionSetupServiceProvider = FutureProvider<SessionSetupService>((
  ref,
) async {
  final identityStore = await ref.watch(sessionIdentityStoreProvider.future);
  final lifecycleStore = await ref.watch(sessionLifecycleStoreProvider.future);
  return LocalSessionSetupService(
    ref.watch(backendSessionClientProvider),
    ref.watch(credentialStoreProvider),
    identityStore,
    lifecycleStore,
  );
});
