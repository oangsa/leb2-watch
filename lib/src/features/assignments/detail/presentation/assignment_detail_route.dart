import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_dependencies.dart';
import '../../../../app/design_system/widgets/app_state_view.dart';
import '../../../../app/routing/app_route.dart';
import '../domain/assignment_detail_key.dart';
import 'assignment_detail_page.dart';

const assignmentDetailRouteName = 'assignmentDetail';
const assignmentDetailRoutePath = ':semesterId/:identityKey';

class AssignmentDetailRoute extends ConsumerWidget {
  const AssignmentDetailRoute({
    required this.semesterIdSource,
    required this.identityKeySource,
    super.key,
  });

  final String semesterIdSource;
  final String identityKeySource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = AssignmentDetailKey.tryParse(
      semesterIdSource: semesterIdSource,
      identityKeySource: identityKeySource,
    );
    if (key == null) {
      return AppStateView.error(
        title: 'Assignment link unavailable',
        message: 'This local assignment link is not valid.',
        actionLabel: 'Back to assignments',
        onAction: () => context.go(AppRoute.assignments.path),
      );
    }
    return ref
        .watch(assignmentDetailServiceProvider)
        .when(
          data: (service) => AssignmentDetailPage(
            detailKey: key,
            service: service,
            downloadService: ref.watch(attachmentDownloadServiceProvider),
            canPop: context.canPop(),
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoute.assignments.path);
              }
            },
          ),
          error: (_, _) => AppStateView.error(
            title: 'Assignment details unavailable',
            message:
                'Saved assignment details could not be opened. Check local '
                'storage and try again.',
            actionLabel: 'Retry',
            onAction: () {
              ref.invalidate(assignmentDetailServiceProvider);
              ref.invalidate(assignmentDetailStoreProvider);
            },
          ),
          loading: () => const AppStateView.loading(
            title: 'Opening saved assignment',
            message: 'Reading assignment details from this device.',
          ),
        );
  }
}
