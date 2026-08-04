import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/diagnostics/application/synchronization_diagnostics_service.dart';
import 'package:leb2_watch/src/features/diagnostics/domain/synchronization_diagnostics.dart';
import 'package:leb2_watch/src/features/diagnostics/presentation/synchronization_diagnostics_page.dart';

void main() {
  testWidgets('renders local diagnostics before scheduler status completes', (
    tester,
  ) async {
    final scheduler = Completer<BackgroundScheduleStatus>();
    final service = _FakeDiagnosticsService(
      schedulerReader: () => scheduler.future,
    );
    addTearDown(service.close);
    await _pumpPage(tester, service);

    service.emit(_snapshot());
    await tester.pump();

    expect(find.text('Synchronization diagnostics'), findsOneWidget);
    expect(find.text('Waiting to recover'), findsOneWidget);
    expect(find.text('18 saved for the selected semester'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Checking scheduler status'), findsOneWidget);

    scheduler.complete(
      BackgroundScheduleActive(
        approximateNextCheckAtUtc: DateTime.utc(2026, 7, 26, 15),
      ),
    );
    await tester.pump();

    expect(find.text('Active; timing may vary'), findsOneWidget);
    expect(find.text('Around LOCAL 2026-07-26T15:00:00.000Z'), findsOneWidget);
  });

  testWidgets(
    'refresh reads local and scheduler status without a sync action',
    (tester) async {
      final service = _FakeDiagnosticsService();
      addTearDown(service.close);
      await _pumpPage(tester, service);
      service.emit(_snapshot());
      await tester.pumpAndSettle();

      service.readValue = _snapshot(
        syncState: DiagnosticsSyncState.idle,
        cachedAssignmentCount: 19,
      );
      await tester.tap(find.byKey(const Key('diagnostics-refresh')));
      await tester.pumpAndSettle();

      expect(service.localReadCalls, 1);
      expect(service.schedulerReadCalls, 2);
      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('19 saved for the selected semester'), findsOneWidget);
      expect(
        find.byKey(const Key('diagnostics-refresh-announcement')),
        findsOneWidget,
      );
    },
  );

  testWidgets('later local failure retains last snapshot with stale banner', (
    tester,
  ) async {
    final service = _FakeDiagnosticsService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(_snapshot());
    await tester.pumpAndSettle();

    service.fail(StateError('PRIVATE_STACK_TRACE'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting to recover'), findsOneWidget);
    expect(find.byKey(const Key('diagnostics-local-stale')), findsOneWidget);
    expect(find.textContaining('PRIVATE_STACK_TRACE'), findsNothing);
  });

  testWidgets('resume refreshes only local and scheduler evidence', (
    tester,
  ) async {
    final service = _FakeDiagnosticsService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(_snapshot());
    await tester.pumpAndSettle();
    final schedulerCalls = service.schedulerReadCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(service.localReadCalls, 1);
    expect(service.schedulerReadCalls, schedulerCalls + 1);
  });

  for (final width in <double>[320, 375, 414, 768, 1200]) {
    testWidgets('fits $width px at 200% text with reduced motion', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = _FakeDiagnosticsService();
      addTearDown(service.close);

      await _pumpPage(
        tester,
        service,
        mediaQueryData: const MediaQueryData(
          textScaler: TextScaler.linear(2),
          disableAnimations: true,
        ),
      );
      service.emit(_snapshot());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('synchronization-diagnostics-page')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('exposes a header, status meaning, and refresh action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final service = _FakeDiagnosticsService();
      addTearDown(service.close);
      await _pumpPage(tester, service);
      service.emit(_snapshot());
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.text('Synchronization diagnostics'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(
        find.bySemanticsLabel('Current state: Waiting to recover'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Refresh status'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  SynchronizationDiagnosticsService service, {
  MediaQueryData? mediaQueryData,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: MediaQuery(
        data: mediaQueryData ?? const MediaQueryData(),
        child: Scaffold(
          body: SynchronizationDiagnosticsPage(
            service: service,
            timestampFormatter: (_, timestamp) =>
                'LOCAL ${timestamp.toUtc().toIso8601String()}',
          ),
        ),
      ),
    ),
  );
}

SynchronizationDiagnosticsSnapshot _snapshot({
  DiagnosticsSyncState syncState = DiagnosticsSyncState.recoveryPending,
  int cachedAssignmentCount = 18,
}) {
  return SynchronizationDiagnosticsSnapshot(
    hasActiveSemester: true,
    hasConfiguredTarget: true,
    sessionState: SessionLifecycleState.active,
    cachedAssignmentCount: cachedAssignmentCount,
    syncState: syncState,
    lastAttemptedAtUtc: DateTime.utc(2026, 7, 26, 12),
    lastSuccessfulAtUtc: DateTime.utc(2026, 7, 26, 11),
    lastFailureAtUtc: DateTime.utc(2026, 7, 26, 10),
    lastFailureCategory: DiagnosticsFailureCategory.networkUnavailable,
    backoff: const DiagnosticsBackoffReady(),
  );
}

final class _FakeDiagnosticsService
    implements SynchronizationDiagnosticsService {
  _FakeDiagnosticsService({
    Future<BackgroundScheduleStatus> Function()? schedulerReader,
  }) : schedulerReader =
           schedulerReader ?? (() async => const BackgroundScheduleInactive());

  final _controller =
      StreamController<SynchronizationDiagnosticsSnapshot>.broadcast();
  final Future<BackgroundScheduleStatus> Function() schedulerReader;
  SynchronizationDiagnosticsSnapshot readValue = _snapshot();
  int localReadCalls = 0;
  int schedulerReadCalls = 0;

  void emit(SynchronizationDiagnosticsSnapshot value) => _controller.add(value);

  void fail(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();

  @override
  Stream<SynchronizationDiagnosticsSnapshot> watchLocal() => _controller.stream;

  @override
  Future<SynchronizationDiagnosticsSnapshot> readLocal() async {
    localReadCalls += 1;
    return readValue;
  }

  @override
  Future<BackgroundScheduleStatus> readSchedulerStatus() {
    schedulerReadCalls += 1;
    return schedulerReader();
  }
}
