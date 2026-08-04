import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../application/synchronization_diagnostics_service.dart';
import '../data/synchronization_diagnostics_store.dart';
import 'synchronization_diagnostics_page.dart';

final synchronizationDiagnosticsServiceProvider =
    FutureProvider<SynchronizationDiagnosticsService>((ref) async {
      final database = await ref.watch(appDatabaseProvider.future);
      final scheduler = await ref.watch(backgroundSchedulerProvider.future);
      return LocalSynchronizationDiagnosticsService(
        DriftSynchronizationDiagnosticsStore(database),
        scheduler,
      );
    });

class SynchronizationDiagnosticsRoute extends ConsumerWidget {
  const SynchronizationDiagnosticsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(synchronizationDiagnosticsServiceProvider)
        .when(
          data: (service) => SynchronizationDiagnosticsPage(service: service),
          error: (_, _) => AppStateView.error(
            title: 'Diagnostics unavailable',
            message:
                'Saved operational state could not be opened. No '
                'synchronization was started.',
            actionLabel: 'Retry',
            onAction: () =>
                ref.invalidate(synchronizationDiagnosticsServiceProvider),
          ),
          loading: () => const AppStateView.loading(
            title: 'Opening synchronization diagnostics',
            message: '',
          ),
        );
  }
}
