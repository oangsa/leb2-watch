import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/assignments/detail/presentation/assignment_detail_route.dart';

void main() {
  testWidgets('invalid parameters never load the detail service', (
    tester,
  ) async {
    var loadCalls = 0;
    await tester.pumpWidget(
      _Harness(
        location: '/0/backend%3A1001',
        loader: () {
          loadCalls += 1;
          return _Service();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assignment link unavailable'), findsOneWidget);
    expect(find.textContaining('backend'), findsNothing);
    expect(loadCalls, 0);
  });

  testWidgets('valid route exposes bounded provider loading and error states', (
    tester,
  ) async {
    final pending = Completer<AssignmentDetailService>();
    await tester.pumpWidget(
      _Harness(location: '/101/backend%3A1001', loader: () => pending.future),
    );
    await tester.pump();
    expect(find.text('Opening saved assignment'), findsOneWidget);

    pending.completeError(StateError('PRIVATE_PROVIDER_ERROR'));
    await tester.pumpAndSettle();
    expect(find.text('Assignment details unavailable'), findsOneWidget);
    expect(find.textContaining('PRIVATE_PROVIDER_ERROR'), findsNothing);
  });

  testWidgets('valid route renders the exact decoded local identity', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(
      _Harness(location: '/101/backend%3A1001', loader: () => service),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This assignment is not saved on this device.'),
      findsOneWidget,
    );
    expect(service.keys, [
      AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
    ]);
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.location, required this.loader});

  final String location;
  final FutureOr<AssignmentDetailService> Function() loader;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final GoRouter router = GoRouter(
    initialLocation: widget.location,
    routes: [
      GoRoute(
        path: '/:semesterId/:identityKey',
        builder: (_, state) => AssignmentDetailRoute(
          semesterIdSource: state.pathParameters['semesterId'] ?? '',
          identityKeySource: state.pathParameters['identityKey'] ?? '',
        ),
      ),
      GoRoute(
        path: '/assignments',
        builder: (_, _) => const Text('Assignments'),
      ),
    ],
  );

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        assignmentDetailServiceProvider.overrideWith((_) => widget.loader()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }
}

final class _Service implements AssignmentDetailService {
  final keys = <AssignmentDetailKey>[];

  @override
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key) {
    keys.add(key);
    return Stream.value(
      MissingAssignmentDetail(
        key: key,
        sync: const AssignmentDetailSyncEvidence(
          latestAttemptStatus: null,
          latestAttemptFailureCategory: null,
          latestSuccessCompletedAtUtc: null,
        ),
      ),
    );
  }
}
