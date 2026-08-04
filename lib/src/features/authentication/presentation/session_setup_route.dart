import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/routing/app_flow.dart';
import '../../../app/routing/app_route.dart';
import '../../onboarding/presentation/post_login_permissions.dart';
import 'session_setup_page.dart';

class SessionSetupRoute extends ConsumerWidget {
  const SessionSetupRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(sessionSetupServiceProvider);
    return service.when(
      data: (value) => SessionSetupPage(
        service: value,
        onCompleted: () async {
          // Asking here means the permissions monitoring depends on are
          // requested once, in context, instead of waiting for the user to
          // discover a settings page.
          await requestPostLoginPermissions(context, ref);
          if (!context.mounted) {
            return;
          }
          final flow = ref.read(appFlowControllerProvider);
          if (flow.stage == AppFlowStage.ready) {
            context.go(AppRoute.assignments.path);
          } else {
            flow.updateStage(AppFlowStage.semesterSelection);
          }
        },
      ),
      error: (_, _) => Scaffold(
        body: AppStateView.error(
          title: 'Setup unavailable',
          message: 'Local setup could not be opened. Try again.',
          actionLabel: 'Retry',
          onAction: () {
            ref.invalidate(sessionSetupServiceProvider);
            ref.invalidate(sessionIdentityStoreProvider);
            ref.invalidate(appDatabaseProvider);
          },
        ),
      ),
      loading: () => const Scaffold(
        body: AppStateView.loading(title: 'Preparing…', message: ''),
      ),
    );
  }
}
