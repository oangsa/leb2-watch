import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/routing/app_flow.dart';
import '../../../app/routing/app_route.dart';
import 'semester_selection_page.dart';

class SemesterSelectionRoute extends ConsumerWidget {
  const SemesterSelectionRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(semesterSelectionServiceProvider);
    final lifecycle = ref.watch(sessionLifecycleProvider).value;
    return service.when(
      data: (value) => SemesterSelectionPage(
        service: value,
        sessionLifecycle: lifecycle,
        onReconnect: () {
          final flow = ref.read(appFlowControllerProvider);
          if (flow.stage == AppFlowStage.semesterSelection) {
            flow.updateStage(AppFlowStage.authentication);
          }
          context.push(AppRoute.authentication.path);
        },
        onSelected: () {
          final flow = ref.read(appFlowControllerProvider);
          if (flow.stage == AppFlowStage.semesterSelection) {
            flow.updateStage(AppFlowStage.ready);
          }
          context.go(AppRoute.assignments.path);
        },
      ),
      error: (_, _) => Scaffold(
        body: AppStateView.error(
          title: 'Semester selection unavailable',
          message:
              'Saved semester data could not be opened. Check local storage '
              'and try again.',
          actionLabel: 'Retry',
          onAction: () {
            ref.invalidate(semesterSelectionServiceProvider);
            ref.invalidate(semesterSelectionStoreProvider);
            ref.invalidate(sessionLifecycleStoreProvider);
            ref.invalidate(appDatabaseProvider);
          },
        ),
      ),
      loading: () => const Scaffold(
        body: AppStateView.loading(
          title: 'Preparing semesters',
          message: 'Opening saved data on this device.',
        ),
      ),
    );
  }
}
