import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/routing/app_route.dart';
import 'course_preferences_page.dart';

class CoursePreferencesRoute extends ConsumerWidget {
  const CoursePreferencesRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(coursePreferencesServiceProvider)
        .when(
          data: (service) => CoursePreferencesPage(
            service: service,
            onChooseSemester: () => context.go(AppRoute.semesters.path),
          ),
          error: (_, _) => AppStateView.error(
            title: 'Course controls unavailable',
            message:
                'Saved course data could not be opened. Check local storage and '
                'try again.',
            actionLabel: 'Retry',
            onAction: () {
              ref.invalidate(courseEffectPolicyReaderProvider);
              ref.invalidate(coursePreferencesServiceProvider);
              ref.invalidate(coursePreferencesStoreProvider);
              ref.invalidate(appDatabaseProvider);
            },
          ),
          loading: () => const AppStateView.loading(
            title: 'Preparing course controls',
            message: 'Opening saved data on this device.',
          ),
        );
  }
}
