import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/semesters/application/semester_selection_service.dart';
import 'package:leb2_watch/src/features/semesters/data/semester_selection_store.dart';
import 'package:leb2_watch/src/features/semesters/presentation/semester_selection_page.dart';

void main() {
  testWidgets('renders cached rows before delayed refresh completes', (
    tester,
  ) async {
    final refresh = Completer<SemesterRefreshResult>();
    final service = _FakeSemesterSelectionService(refreshGate: refresh);

    await _pumpPage(tester, service: service);

    expect(find.text('Semester 202'), findsOneWidget);
    expect(find.text('Semester 101'), findsOneWidget);
    expect(find.byKey(const Key('semester-inline-progress')), findsOneWidget);
    expect(find.text('Loading semesters'), findsNothing);
    expect(service.readCalls, 1);
    expect(service.refreshCalls, 1);

    refresh.complete(
      SemesterRefreshSuccess(
        SemesterCatalog(
          semesterIds: const [303, 202, 101],
          activeSemesterId: 202,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Semester 303'), findsOneWidget);
    expect(find.byKey(const Key('semester-inline-progress')), findsNothing);
  });

  testWidgets('offline, stale, and expired states keep cached rows usable', (
    tester,
  ) async {
    for (final testCase
        in <
          ({
            SemesterRefreshResult result,
            SessionLifecycleSnapshot lifecycle,
            Key banner,
          })
        >[
          (
            result: const SemesterRefreshFailure(NetworkUnavailableFailure()),
            lifecycle: _active,
            banner: const Key('semester-offline-banner'),
          ),
          (
            result: const SemesterRefreshFailure(InvalidResponseFailure()),
            lifecycle: _active,
            banner: const Key('semester-stale-banner'),
          ),
          (
            result: const SemesterRefreshFailure(SessionExpiredFailure()),
            lifecycle: _expired,
            banner: const Key('semester-session-expired'),
          ),
        ]) {
      final service = _FakeSemesterSelectionService(
        refreshResult: testCase.result,
      );
      await _pumpPage(tester, service: service, lifecycle: testCase.lifecycle);
      await tester.pumpAndSettle();

      expect(find.byKey(testCase.banner), findsOneWidget);
      expect(find.text('Semester 202'), findsOneWidget);
      await tester.tap(find.byKey(const Key('semester-row-101')));
      await tester.pump();
      expect(service.selectCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final testCase
      in <({AccessKeyFailureReason reason, String message, String action})>[
        (
          reason: AccessKeyFailureReason.invalid,
          message: 'missing or invalid',
          action: 'Reconnect',
        ),
        (
          reason: AccessKeyFailureReason.notActivated,
          message: 'not activated',
          action: 'Reconnect',
        ),
        (
          reason: AccessKeyFailureReason.identityMismatch,
          message: 'does not match this account',
          action: 'Reconnect',
        ),
        (
          reason: AccessKeyFailureReason.reauthenticationRequired,
          message: 'Sign in again with username and password',
          action: 'Reconnect',
        ),
        (
          reason: AccessKeyFailureReason.storeUnavailable,
          message: 'unavailable. Try again later.',
          action: 'Retry',
        ),
      ]) {
    testWidgets(
      'access-key ${testCase.reason.name} keeps cached rows and guidance',
      (tester) async {
        final service = _FakeSemesterSelectionService(
          refreshResult: SemesterRefreshFailure(
            AccessKeyFailure(testCase.reason),
          ),
        );
        await _pumpPage(tester, service: service);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('semester-access-key-banner')),
          findsOneWidget,
        );
        expect(find.textContaining(testCase.message), findsOneWidget);
        expect(find.text(testCase.action), findsOneWidget);
        expect(find.text('Semester 202'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('manual refresh is accessible and rapid taps do not duplicate', (
    tester,
  ) async {
    final first = Completer<SemesterRefreshResult>();
    final service = _FakeSemesterSelectionService(refreshGate: first);
    await _pumpPage(tester, service: service);

    expect(find.byTooltip('Refresh semesters'), findsOneWidget);
    expect(service.refreshCalls, 1);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('semester-refresh-button')),
    );
    expect(button.onPressed, isNull);

    first.complete(const SemesterRefreshFailure(InvalidResponseFailure()));
    await tester.pumpAndSettle();
    final second = Completer<SemesterRefreshResult>();
    service.refreshGate = second;

    await tester.tap(find.byKey(const Key('semester-refresh-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('semester-refresh-button')));
    expect(service.refreshCalls, 2);

    second.complete(
      SemesterRefreshSuccess(
        SemesterCatalog(semesterIds: const [202, 101], activeSemesterId: 202),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('active row exposes selected semantics', (tester) async {
    await _pumpPage(tester);
    await tester.pumpAndSettle();

    final selected = tester.getSemantics(
      find.byKey(const Key('semester-row-202')),
    );
    final other = tester.getSemantics(
      find.byKey(const Key('semester-row-101')),
    );
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    expect(selected.label, 'Semester 202');
    expect(selected.value, 'Selected on this device');
    expect(other.flagsCollection.isSelected, Tristate.isFalse);
    expect(other.flagsCollection.isButton, isTrue);
    expect(other.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('selection persists and completes exactly once', (tester) async {
    var completions = 0;
    final service = _FakeSemesterSelectionService();
    await _pumpPage(
      tester,
      service: service,
      onSelected: () => completions += 1,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('semester-row-101')));
    await tester.pumpAndSettle();

    expect(service.selectCalls, 1);
    expect(service.lastSelectedId, 101);
    expect(completions, 1);
    expect(
      tester
          .getSemantics(find.byKey(const Key('semester-row-101')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets(
    'pending navigation keeps rows disabled and suppresses a second selection',
    (tester) async {
      final navigation = Completer<void>();
      var navigationCalls = 0;
      final service = _FakeSemesterSelectionService();
      await _pumpPage(
        tester,
        service: service,
        onSelected: () {
          navigationCalls += 1;
          return navigation.future;
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('semester-row-101')));
      await tester.pump();
      expect(service.selectCalls, 1);
      expect(navigationCalls, 1);
      expect(
        tester
            .getSemantics(find.byKey(const Key('semester-row-202')))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );

      await tester.tap(
        find.byKey(const Key('semester-row-202')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(service.selectCalls, 1);
      expect(navigationCalls, 1);

      navigation.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('selection failure preserves active row and does not navigate', (
    tester,
  ) async {
    var completions = 0;
    final service = _FakeSemesterSelectionService(
      selectResult: const SemesterSelectionFailure(),
    );
    await _pumpPage(
      tester,
      service: service,
      onSelected: () => completions += 1,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('semester-row-101')));
    await tester.pumpAndSettle();

    expect(completions, 0);
    expect(find.byKey(const Key('semester-selection-error')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('semester-row-202')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('navigation retry does not save the selection again', (
    tester,
  ) async {
    var navigationCalls = 0;
    final service = _FakeSemesterSelectionService();
    await _pumpPage(
      tester,
      service: service,
      onSelected: () {
        navigationCalls += 1;
        if (navigationCalls == 1) {
          throw StateError('Synthetic navigation failure.');
        }
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('semester-row-101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('semester-navigation-error')), findsOneWidget);

    await tester.tap(find.text('Open assignments'));
    await tester.pumpAndSettle();
    expect(service.selectCalls, 1);
    expect(navigationCalls, 2);
    expect(find.byKey(const Key('semester-navigation-error')), findsNothing);
  });

  testWidgets(
    'empty or ambiguous response never claims there are no semesters',
    (tester) async {
      final service = _FakeSemesterSelectionService(
        cached: SemesterCatalog.empty(),
        refreshResult: const SemesterRefreshFailure(InvalidResponseFailure()),
      );

      await _pumpPage(tester, service: service);
      await tester.pumpAndSettle();

      expect(find.text('Semesters unavailable'), findsOneWidget);
      expect(find.textContaining('Nothing was returned'), findsOneWidget);
      expect(find.textContaining('No semesters'), findsNothing);
    },
  );

  testWidgets('keyboard activation selects a focused semester row', (
    tester,
  ) async {
    final service = _FakeSemesterSelectionService();
    await _pumpPage(tester, service: service);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(service.selectCalls, 1);
    expect(service.lastSelectedId, 202);
  });

  for (final width in [320.0, 375.0, 414.0, 768.0, 1200.0]) {
    testWidgets('fits $width logical pixels at 200 percent text', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        size: Size(width, 900),
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose semester'), findsOneWidget);
      if (find.text('Semester 202').evaluate().isEmpty) {
        await tester.drag(
          find.byKey(const Key('semester-list')),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Semester 202'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('maximum int32 label fits compact layout at 200 percent text', (
    tester,
  ) async {
    final service = _FakeSemesterSelectionService(
      cached: SemesterCatalog(
        semesterIds: const [2147483647],
        activeSemesterId: 2147483647,
      ),
    );
    await _pumpPage(
      tester,
      service: service,
      size: const Size(320, 900),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    if (find.text('Semester 2147483647').evaluate().isEmpty) {
      await tester.drag(
        find.byKey(const Key('semester-list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Semester 2147483647'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('semester-row-2147483647')))
          .label,
      'Semester 2147483647',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports dark theme and reduced motion', (tester) async {
    await _pumpPage(
      tester,
      brightness: Brightness.dark,
      disableAnimations: true,
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Choose semester'))).brightness,
      Brightness.dark,
    );
    expect(find.text('Semester 202'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _active = SessionLifecycleSnapshot(
  state: SessionLifecycleState.active,
  revision: 1,
);
const _expired = SessionLifecycleSnapshot(
  state: SessionLifecycleState.expired,
  revision: 1,
);

Future<void> _pumpPage(
  WidgetTester tester, {
  _FakeSemesterSelectionService? service,
  FutureOr<void> Function()? onSelected,
  SessionLifecycleSnapshot lifecycle = _active,
  Size size = const Size(800, 900),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) async {
  final resolvedService = service ?? _FakeSemesterSelectionService();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: SemesterSelectionPage(
          service: resolvedService,
          sessionLifecycle: lifecycle,
          onReconnect: () {},
          onSelected: onSelected ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _FakeSemesterSelectionService implements SemesterSelectionService {
  _FakeSemesterSelectionService({
    SemesterCatalog? cached,
    this.refreshGate,
    this.refreshResult,
    this.selectResult,
  }) : cached =
           cached ??
           SemesterCatalog(
             semesterIds: const [202, 101],
             activeSemesterId: 202,
           );

  SemesterCatalog cached;
  Completer<SemesterRefreshResult>? refreshGate;
  SemesterRefreshResult? refreshResult;
  SemesterSelectionResult? selectResult;
  int readCalls = 0;
  int refreshCalls = 0;
  int selectCalls = 0;
  int? lastSelectedId;

  @override
  Future<SemesterCatalog> readCached() async {
    readCalls += 1;
    return cached;
  }

  @override
  Future<SemesterRefreshResult> refresh({
    SemesterRefreshCancellation? cancellation,
  }) async {
    refreshCalls += 1;
    final gate = refreshGate;
    if (gate != null) {
      return gate.future;
    }
    return refreshResult ?? SemesterRefreshSuccess(cached);
  }

  @override
  Future<SemesterSelectionResult> select(int semesterId) async {
    selectCalls += 1;
    lastSelectedId = semesterId;
    final result = selectResult;
    if (result != null) {
      return result;
    }
    cached = SemesterCatalog(
      semesterIds: cached.semesterIds,
      activeSemesterId: semesterId,
    );
    return SemesterSelectionSuccess(cached);
  }
}
