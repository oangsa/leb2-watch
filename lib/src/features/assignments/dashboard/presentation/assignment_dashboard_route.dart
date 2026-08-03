import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_dependencies.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/routing/app_route.dart';
import '../../detail/presentation/assignment_detail_route.dart';
import 'assignment_dashboard_page.dart';

class AssignmentDashboardRoute extends ConsumerWidget {
  const AssignmentDashboardRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(assignmentDashboardServiceProvider)
        .when(
          data: (service) => AssignmentDashboardPage(
            service: service,
            onChooseSemester: () => context.go(AppRoute.semesters.path),
            onOpenAssignment: (key) => context.pushNamed(
              assignmentDetailRouteName,
              pathParameters: key.pathParameters,
            ),
          ),
          error: (_, _) => AppStateView.error(
            title: 'Assignments unavailable',
            message:
                'Saved assignments could not be opened. Check local storage '
                'and try again.',
            actionLabel: 'Retry',
            onAction: () {
              ref.invalidate(assignmentDashboardServiceProvider);
              ref.invalidate(assignmentDashboardStoreProvider);
              ref.invalidate(assignmentSyncServiceProvider);
              ref.invalidate(appDatabaseProvider);
            },
          ),
          loading: () => const AppStateView.loading(
            title: 'Opening saved assignments',
            message: 'Reading the assignment cache on this device.',
          ),
        );
  }
}
