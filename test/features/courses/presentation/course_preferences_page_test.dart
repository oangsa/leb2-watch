import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/courses/application/course_preferences_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';
import 'package:leb2_watch/src/features/courses/presentation/course_preferences_page.dart';

void main() {
  testWidgets('renders the cached control ledger with exact count meanings', (
    tester,
  ) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(_catalog());
    await tester.pump();

    expect(find.text('Course controls'), findsOneWidget);
    expect(find.text('Semester 101 · saved on this device'), findsOneWidget);
    expect(
      find.textContaining('viewing this page does not clear them'),
      findsOneWidget,
    );
    expect(find.text('Distributed Systems'), findsOneWidget);
    expect(find.text('New activities: 2'), findsOneWidget);
    expect(find.text('Upcoming deadlines: 3'), findsOneWidget);
    expect(find.textContaining('does not skip that download'), findsOneWidget);

    final row = tester.getSemantics(
      find.byKey(const Key('course-preference-row-3001')),
    );
    expect(row.label, contains('Distributed Systems'));
    expect(row.label, contains('course 3001'));
    final mute = tester.getSemantics(find.byKey(const Key('course-mute-3001')));
    final background = tester.getSemantics(
      find.byKey(const Key('course-background-3001')),
    );
    expect(mute.label, contains('Mute notifications'));
    expect(mute.flagsCollection.isToggled, Tristate.isFalse);
    expect(mute.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(background.label, contains('Background monitoring'));
    expect(background.flagsCollection.isToggled, Tristate.isTrue);
  });

  testWidgets(
    'pessimistic mute write disables the row until saved data emits',
    (tester) async {
      final service = _FakeCoursePreferencesService();
      addTearDown(service.close);
      await _pumpPage(tester, service);
      service.emit(_catalog());
      await tester.pump();
      final result = Completer<CoursePreferenceUpdateResult>();
      service.nextMuteResult = result.future;

      await tester.tap(find.byKey(const Key('course-mute-3001')));
      await tester.pump();

      expect(service.muteCalls, 1);
      expect(service.lastKey, const CourseKey(semesterId: 101, courseId: 3001));
      expect(service.lastValue, isTrue);
      expect(
        _switchTile(tester, const Key('course-mute-3001')).onChanged,
        isNull,
      );
      expect(
        _switchTile(tester, const Key('course-background-3001')).onChanged,
        isNull,
      );
      expect(
        find.byKey(const Key('course-preference-progress')),
        findsOneWidget,
      );
      expect(
        _switchTile(tester, const Key('course-mute-3001')).value,
        isFalse,
        reason: 'the visible switch does not update before persistence',
      );

      result.complete(const CoursePreferenceUpdateSuccess());
      await tester.pump();
      expect(
        _switchTile(tester, const Key('course-mute-3001')).onChanged,
        isNull,
        reason: 'success alone does not invent saved state',
      );

      service.emit(
        _catalog(preference: const CoursePreference(notificationsMuted: true)),
      );
      await tester.pump();
      expect(_switchTile(tester, const Key('course-mute-3001')).value, isTrue);
      expect(
        _switchTile(tester, const Key('course-background-3001')).onChanged,
        isNotNull,
      );
    },
  );

  testWidgets(
    'failed write keeps persisted state and exposes retry-safe copy',
    (tester) async {
      final service = _FakeCoursePreferencesService()
        ..nextBackgroundResult = Future.value(
          const CoursePreferenceUpdateFailure(),
        );
      addTearDown(service.close);
      await _pumpPage(tester, service);
      service.emit(_catalog());
      await tester.pump();

      await tester.tap(find.byKey(const Key('course-background-3001')));
      await tester.pumpAndSettle();

      expect(service.backgroundCalls, 1);
      expect(
        _switchTile(tester, const Key('course-background-3001')).value,
        isTrue,
      );
      expect(
        find.byKey(const Key('course-preference-write-error')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your previous setting is still in use'),
        findsOneWidget,
      );
    },
  );

  testWidgets('stale write keeps persisted state and explains the fence', (
    tester,
  ) async {
    final service = _FakeCoursePreferencesService()
      ..nextMuteResult = Future.value(const CoursePreferenceUpdateStale());
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(_catalog());
    await tester.pump();

    await tester.tap(find.byKey(const Key('course-mute-3001')));
    await tester.pumpAndSettle();

    expect(_switchTile(tester, const Key('course-mute-3001')).value, isFalse);
    expect(find.textContaining('visible course changed'), findsOneWidget);
    expect(
      _switchTile(tester, const Key('course-background-3001')).onChanged,
      isNotNull,
    );
  });

  testWidgets('no-active and active-empty states are truthful', (tester) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    var chooseCalls = 0;
    await _pumpPage(tester, service, onChooseSemester: () => chooseCalls += 1);

    service.emit(
      ActiveCourseCatalog(activeSemesterId: null, courses: const []),
    );
    await tester.pump();
    expect(find.text('Choose a semester first'), findsOneWidget);
    await tester.tap(find.text('Choose semester'));
    expect(chooseCalls, 1);

    service.emit(ActiveCourseCatalog(activeSemesterId: 101, courses: const []));
    await tester.pump();
    expect(find.text('No saved courses yet'), findsOneWidget);
    expect(find.textContaining('successful assignment sync'), findsOneWidget);
  });

  testWidgets('stream errors are redacted and retry subscribes again', (
    tester,
  ) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service);

    service.fail(StateError('<PRIVATE_COURSE_DATA>'));
    await tester.pump();
    expect(find.text('Saved courses unavailable'), findsOneWidget);
    expect(find.textContaining('<PRIVATE_COURSE_DATA>'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(service.watchCalls, 2);
    service.emit(_catalog());
    await tester.pump();
    expect(find.text('Distributed Systems'), findsOneWidget);
  });

  testWidgets('semantic activation invokes a course control', (tester) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(_catalog());
    await tester.pump();

    tester.semantics.tap(
      find.semantics.byLabel(
        'Mute notifications. Suppress local notifications for this course.',
      ),
    );
    await tester.pump();

    expect(service.muteCalls, 1);
  });

  for (final testCase in <({double width, Brightness brightness})>[
    (width: 320, brightness: Brightness.light),
    (width: 375, brightness: Brightness.dark),
    (width: 414, brightness: Brightness.light),
    (width: 768, brightness: Brightness.dark),
    (width: 1200, brightness: Brightness.light),
  ]) {
    testWidgets(
      'fits ${testCase.width}px at 200% text in ${testCase.brightness.name}',
      (tester) async {
        final service = _FakeCoursePreferencesService();
        addTearDown(service.close);
        await _pumpPage(
          tester,
          service,
          size: Size(testCase.width, 900),
          textScale: 2,
          brightness: testCase.brightness,
          reduceMotion: true,
        );
        service.emit(_catalog());
        await tester.pump();

        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Distributed Systems'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Distributed Systems'), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);
      },
    );
  }

  testWidgets('large cached catalogs remain lazily built', (tester) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service, size: const Size(375, 700));
    service.emit(
      ActiveCourseCatalog(
        activeSemesterId: 101,
        courses: [
          for (var index = 0; index < 100; index++)
            _summary(id: 3000 + index, name: 'Course $index'),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Course 0'), findsOneWidget);
    expect(find.text('Course 99'), findsNothing);
  });
}

SwitchListTile _switchTile(WidgetTester tester, Key key) {
  return tester.widget<SwitchListTile>(
    find.descendant(of: find.byKey(key), matching: find.byType(SwitchListTile)),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeCoursePreferencesService service, {
  VoidCallback? onChooseSemester,
  Size size = const Size(800, 900),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: CoursePreferencesPage(
          service: service,
          onChooseSemester: onChooseSemester ?? () {},
        ),
      ),
    ),
  );
}

ActiveCourseCatalog _catalog({
  CoursePreference preference = const CoursePreference(),
}) {
  return ActiveCourseCatalog(
    activeSemesterId: 101,
    courses: [
      _summary(id: 3001, name: 'Distributed Systems', preference: preference),
    ],
  );
}

CourseSummary _summary({
  required int id,
  required String name,
  CoursePreference preference = const CoursePreference(),
}) {
  return CourseSummary(
    key: CourseKey(semesterId: 101, courseId: id),
    name: name,
    postBaselineActivityCount: 2,
    notReportedExceededDeadlineCount: 3,
    preference: preference,
  );
}

final class _FakeCoursePreferencesService implements CoursePreferencesService {
  _FakeCoursePreferencesService();

  StreamController<ActiveCourseCatalog> _controller =
      StreamController<ActiveCourseCatalog>.broadcast(sync: true);
  Future<CoursePreferenceUpdateResult> nextMuteResult = Future.value(
    const CoursePreferenceUpdateSuccess(),
  );
  Future<CoursePreferenceUpdateResult> nextBackgroundResult = Future.value(
    const CoursePreferenceUpdateSuccess(),
  );
  int watchCalls = 0;
  int muteCalls = 0;
  int backgroundCalls = 0;
  CourseKey? lastKey;
  bool? lastValue;

  void emit(ActiveCourseCatalog catalog) => _controller.add(catalog);

  void fail(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();

  @override
  Stream<ActiveCourseCatalog> watchCatalog() {
    watchCalls += 1;
    if (_controller.isClosed) {
      _controller = StreamController<ActiveCourseCatalog>.broadcast(sync: true);
    }
    return _controller.stream;
  }

  @override
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) {
    backgroundCalls += 1;
    lastKey = key;
    lastValue = enabled;
    return nextBackgroundResult;
  }

  @override
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) {
    muteCalls += 1;
    lastKey = key;
    lastValue = muted;
    return nextMuteResult;
  }
}
