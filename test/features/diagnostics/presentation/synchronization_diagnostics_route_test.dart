import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/diagnostics/application/synchronization_diagnostics_service.dart';
import 'package:leb2_watch/src/features/diagnostics/domain/synchronization_diagnostics.dart';
import 'package:leb2_watch/src/features/diagnostics/presentation/synchronization_diagnostics_route.dart';

void main() {
  testWidgets('route exposes bounded local-storage loading state', (
    tester,
  ) async {
    final pending = Completer<SynchronizationDiagnosticsService>();
    await tester.pumpWidget(_RouteHarness(loader: () => pending.future));
    await tester.pump();

    expect(find.text('Opening synchronization diagnostics'), findsOneWidget);
    expect(find.text(''), findsOneWidget);

    pending.complete(const _RouteDiagnosticsService());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('synchronization-diagnostics-page')),
      findsOneWidget,
    );
  });

  testWidgets('route redacts provider errors and retries feature composition', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _RouteHarness(
        loader: () {
          calls += 1;
          if (calls == 1) {
            throw StateError('PRIVATE_PROVIDER_ERROR');
          }
          return const _RouteDiagnosticsService();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics unavailable'), findsOneWidget);
    expect(find.textContaining('PRIVATE_PROVIDER_ERROR'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(
      find.byKey(const Key('synchronization-diagnostics-page')),
      findsOneWidget,
    );
  });
}

class _RouteHarness extends StatelessWidget {
  const _RouteHarness({required this.loader});

  final FutureOr<SynchronizationDiagnosticsService> Function() loader;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        synchronizationDiagnosticsServiceProvider.overrideWith((_) => loader()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const Scaffold(body: SynchronizationDiagnosticsRoute()),
      ),
    );
  }
}

final class _RouteDiagnosticsService
    implements SynchronizationDiagnosticsService {
  const _RouteDiagnosticsService();

  @override
  Stream<SynchronizationDiagnosticsSnapshot> watchLocal() => Stream.value(
    SynchronizationDiagnosticsSnapshot(
      hasActiveSemester: false,
      hasConfiguredTarget: false,
      sessionState: SessionLifecycleState.unknown,
      cachedAssignmentCount: null,
      syncState: DiagnosticsSyncState.notConfigured,
      lastAttemptedAtUtc: null,
      lastSuccessfulAtUtc: null,
      lastFailureAtUtc: null,
      lastFailureCategory: null,
      backoff: const DiagnosticsBackoffReady(),
    ),
  );

  @override
  Future<SynchronizationDiagnosticsSnapshot> readLocal() => watchLocal().first;

  @override
  Future<BackgroundScheduleStatus> readSchedulerStatus() async =>
      const BackgroundScheduleInactive();
}
