import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/routing/app_flow.dart';
import 'application/local_data_deletion_service.dart';
import 'application/local_data_deletion_ports.dart';
import 'data/local_data_cleanup_adapters.dart';
import 'domain/local_data_deletion.dart';
import 'presentation/local_data_deletion_flow_service.dart';

final localApplicationCacheCleanupProvider =
    Provider<LocalApplicationCacheCleanup>((ref) {
      return OwnedLocalApplicationCacheCleanup();
    });

final localDataDeletionServiceProvider = Provider<LocalDataDeletionService>((
  ref,
) {
  final capabilities = ref
      .read(localNotificationsPlatformProvider)
      .capabilities;
  return LocalDataDeletionCoordinator(
    background: PlatformLocalDataBackgroundCleanup(
      () => ref.read(backgroundSchedulerProvider.future),
      ref.read(backgroundSchedulerPlatformProvider),
    ),
    autostart: PlatformLocalDataAutostartCleanup(
      ref.read(desktopAutostartServiceProvider),
    ),
    notifications: PlatformLocalDataNotificationCleanup(
      ref.read(localNotificationServiceProvider),
      ref.read(localNotificationDeletionControlProvider),
      capabilities,
    ),
    credentials: SecureLocalDataCredentialCleanup(
      ref.read(credentialStoreProvider),
    ),
    database: DriftLocalDataDatabaseCleanup(
      ref.read(appDatabaseManagerProvider),
      ref.read(localDatabaseStorageProvider),
    ),
    cache: ref.read(localApplicationCacheCleanupProvider),
    providerGraph: CallbackLocalProviderGraphReset(() async {
      ref.invalidate(appDatabaseProvider);
    }),
  );
});

final localDataDeletionFlowServiceProvider = Provider<LocalDataDeletionService>(
  (ref) {
    return FlowNavigatingLocalDataDeletionService(
      ref.watch(localDataDeletionServiceProvider),
      ref.read(appFlowControllerProvider),
    );
  },
);
