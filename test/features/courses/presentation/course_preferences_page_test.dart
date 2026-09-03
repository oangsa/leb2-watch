import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/learning_material_models.dart';
import 'package:leb2_watch/src/features/assignments/attachments/application/attachment_download_service.dart';
import 'package:leb2_watch/src/features/assignments/attachments/domain/attachment_download.dart';
import 'package:leb2_watch/src/features/courses/application/course_materials_service.dart';
import 'package:leb2_watch/src/features/courses/application/course_preferences_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';
import 'package:leb2_watch/src/features/courses/presentation/course_preferences_page.dart';

void main() {
  testWidgets('renders courses with exact count meanings', (tester) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(_catalog());
    await tester.pump();

    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Semester 101'), findsOneWidget);
    expect(find.text('Updates follow assignment checks'), findsOneWidget);
    expect(
      find.textContaining('viewing this page does not clear them'),
      findsNothing,
    );
    expect(find.text('Distributed Systems'), findsOneWidget);
    expect(find.byKey(const Key('course-settings-button')), findsOneWidget);

    await _openCourseSettings(tester);

    expect(find.text('Course settings'), findsOneWidget);
    expect(find.text('Mute all'), findsNothing);
    expect(find.text('Stop all checks'), findsNothing);
    expect(find.text('2 new · 3 due'), findsOneWidget);
    expect(find.text('Checks for updates while closed.'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('course-preference-row-3001')),
        matching: find.byType(Card),
      ),
      findsNothing,
    );

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

  testWidgets('shows course files and saves a selected download', (
    tester,
  ) async {
    final service = _FakeCoursePreferencesService();
    final materialsService = _FakeCourseMaterialsService(
      CourseMaterialsCatalog(
        semesterId: 101,
        classId: 3001,
        userId: 2001,
        materials: [
          const LearningMaterial(
            id: 5001,
            classId: 3001,
            title: 'Reading',
            description: '<p>Read this.</p>',
            fileCount: 2,
            fileMaterials: [
              LearningMaterialFile(
                id: 6001,
                displayName: 'reading.pdf',
                fileSize: '585 KB',
                fileType: 'application/pdf',
              ),
              LearningMaterialFile(
                id: 6002,
                displayName: 'notes.txt',
                fileSize: '2 KB',
                fileType: 'text/plain',
              ),
            ],
          ),
        ],
      ),
    );
    final learningClient = _FakeLearningClient();
    final sink = _RecordingSink();
    final downloadService = AttachmentDownloadService(
      () => throw UnimplementedError(),
      sink,
      learningActivityClient: () => learningClient,
    );
    addTearDown(service.close);

    await _pumpPage(
      tester,
      service,
      size: const Size(800, 1400),
      materialsService: materialsService,
      downloadService: downloadService,
    );
    service.emit(_catalog());
    await tester.pump();
    await tester.pump();

    expect(materialsService.keys, [
      const CourseKey(semesterId: 101, courseId: 3001),
    ]);
    expect(find.text('Course files'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('reading.pdf'), findsOneWidget);
    expect(
      find.byKey(const Key('download-learning-material-all-5001')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('download-learning-material-5001-6001')),
    );
    await tester.pumpAndSettle();

    expect(learningClient.attachmentCalls.single, (
      semesterId: 101,
      classId: 3001,
      materialId: 5001,
      attachmentId: 6001,
      userId: 2001,
    ));
    expect(find.text('Saved to /saved/reading.pdf'), findsOneWidget);
    expect(sink.fileNames, ['reading.pdf']);
  });

  testWidgets('keeps course-file errors compact and retryable', (tester) async {
    final service = _FakeCoursePreferencesService();
    final materialsService = _FakeCourseMaterialsService(null)
      ..failure = StateError('private backend details');
    addTearDown(service.close);

    await _pumpPage(
      tester,
      service,
      size: const Size(800, 1400),
      materialsService: materialsService,
    );
    service.emit(_catalog());
    await tester.pump();
    await tester.pump();

    expect(find.text('Course files unavailable.'), findsOneWidget);
    expect(find.textContaining('private backend details'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    materialsService.failure = null;
    materialsService.catalog = CourseMaterialsCatalog(
      semesterId: 101,
      classId: 3001,
      userId: 2001,
      materials: const [],
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No files'), findsOneWidget);
    expect(materialsService.keys, hasLength(2));
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

      await _openCourseSettings(tester);
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

      await _openCourseSettings(tester);
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

    await _openCourseSettings(tester);
    await tester.tap(find.byKey(const Key('course-mute-3001')));
    await tester.pumpAndSettle();

    expect(_switchTile(tester, const Key('course-mute-3001')).value, isFalse);
    expect(find.textContaining('course changed'), findsOneWidget);
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
    expect(find.text('Select a semester to see courses.'), findsOneWidget);
    await tester.tap(find.text('Choose semester'));
    expect(chooseCalls, 1);

    service.emit(ActiveCourseCatalog(activeSemesterId: 101, courses: const []));
    await tester.pump();
    expect(find.text('No saved courses yet'), findsOneWidget);
    expect(find.text('Sync this semester to see courses.'), findsOneWidget);
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

    await _openCourseSettings(tester);
    tester.semantics.tap(
      find.semantics.byLabel('Mute notifications. Alerts for this course.'),
    );
    await tester.pump();

    expect(service.muteCalls, 1);
  });

  testWidgets('selects a course before showing its settings', (tester) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(
      ActiveCourseCatalog(
        activeSemesterId: 101,
        courses: [
          _summary(id: 3001, name: 'Distributed Systems'),
          _summary(id: 3002, name: 'Computer Networks'),
        ],
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('course-preference-row-3001')), findsNothing);
    expect(find.byKey(const Key('course-preference-row-3002')), findsNothing);

    await _chooseCourse(tester, 'Computer Networks');
    await _openCourseSettings(tester);

    expect(find.byKey(const Key('course-preference-row-3001')), findsNothing);
    expect(find.byKey(const Key('course-preference-row-3002')), findsOneWidget);
  });

  testWidgets('removed selected course reconciles to the first saved course', (
    tester,
  ) async {
    final service = _FakeCoursePreferencesService();
    addTearDown(service.close);
    await _pumpPage(tester, service);
    service.emit(
      ActiveCourseCatalog(
        activeSemesterId: 101,
        courses: [
          _summary(id: 3001, name: 'Distributed Systems'),
          _summary(id: 3002, name: 'Computer Networks'),
        ],
      ),
    );
    await tester.pump();
    await _chooseCourse(tester, 'Computer Networks');

    service.emit(
      ActiveCourseCatalog(
        activeSemesterId: 101,
        courses: [_summary(id: 3001, name: 'Distributed Systems')],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .initialValue,
      3001,
    );
    expect(find.byKey(const Key('course-preference-row-3001')), findsNothing);
    expect(find.byKey(const Key('course-preference-row-3002')), findsNothing);
    await _openCourseSettings(tester);
    expect(find.byKey(const Key('course-preference-row-3001')), findsOneWidget);
    expect(find.byKey(const Key('course-preference-row-3002')), findsNothing);
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
        await _openCourseSettings(tester);
        expect(
          find.byKey(const Key('course-preference-row-3001')),
          findsOneWidget,
        );
        expect(find.byType(ListView), findsOneWidget);
      },
    );
  }

  testWidgets('large catalogs render settings for only the selected course', (
    tester,
  ) async {
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

    await _openCourseSettings(tester);
    expect(find.byKey(const Key('course-preference-row-3000')), findsOneWidget);
    expect(find.byKey(const Key('course-preference-row-3099')), findsNothing);
  });
}

Future<void> _openCourseSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('course-settings-button')));
  await tester.pumpAndSettle();
}

Future<void> _chooseCourse(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
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
  CourseMaterialsService? materialsService,
  AttachmentDownloadService? downloadService,
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
          materialsService: materialsService,
          downloadService: downloadService,
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
  final List<CourseKey> muteKeys = [];
  final List<CourseKey> backgroundKeys = [];
  final List<CoursePreferenceUpdateResult> muteResults = [];
  final List<CoursePreferenceUpdateResult> backgroundResults = [];
  final StreamController<CourseGlobalPreference> _globalController =
      StreamController<CourseGlobalPreference>.broadcast(sync: true);
  CourseGlobalPreference globalPreference = const CourseGlobalPreference();
  CourseKey? lastKey;
  bool? lastValue;

  void emit(ActiveCourseCatalog catalog) => _controller.add(catalog);

  void fail(Object error) => _controller.addError(error);

  Future<void> close() async {
    await _controller.close();
    await _globalController.close();
  }

  @override
  Stream<ActiveCourseCatalog> watchCatalog() {
    watchCalls += 1;
    if (_controller.isClosed) {
      _controller = StreamController<ActiveCourseCatalog>.broadcast(sync: true);
    }
    return _controller.stream;
  }

  @override
  Stream<CourseGlobalPreference> watchGlobalPreference() async* {
    yield globalPreference;
    yield* _globalController.stream;
  }

  @override
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) {
    backgroundCalls += 1;
    backgroundKeys.add(key);
    lastKey = key;
    lastValue = enabled;
    if (backgroundResults.isNotEmpty) {
      return Future.value(backgroundResults.removeAt(0));
    }
    return nextBackgroundResult;
  }

  @override
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) {
    muteCalls += 1;
    muteKeys.add(key);
    lastKey = key;
    lastValue = muted;
    if (muteResults.isNotEmpty) {
      return Future.value(muteResults.removeAt(0));
    }
    return nextMuteResult;
  }

  @override
  Future<CoursePreferenceUpdateResult> setGlobalNotificationsMuted({
    required bool muted,
  }) async {
    globalPreference = CourseGlobalPreference(
      notificationsMuted: muted,
      backgroundMonitoringEnabled: globalPreference.backgroundMonitoringEnabled,
    );
    _globalController.add(globalPreference);
    return const CoursePreferenceUpdateSuccess();
  }

  @override
  Future<CoursePreferenceUpdateResult> setGlobalBackgroundMonitoringEnabled({
    required bool enabled,
  }) async {
    globalPreference = CourseGlobalPreference(
      notificationsMuted: globalPreference.notificationsMuted,
      backgroundMonitoringEnabled: enabled,
    );
    _globalController.add(globalPreference);
    return const CoursePreferenceUpdateSuccess();
  }
}

final class _FakeCourseMaterialsService implements CourseMaterialsService {
  _FakeCourseMaterialsService(this.catalog);

  CourseMaterialsCatalog? catalog;
  Object? failure;
  final List<CourseKey> keys = [];

  @override
  Future<CourseMaterialsCatalog> read(
    CourseKey key, {
    BackendRequestCancellation? cancellation,
  }) async {
    keys.add(key);
    final pending = failure;
    if (pending != null) {
      throw pending;
    }
    final value = catalog;
    if (value == null) {
      throw StateError('missing test catalog');
    }
    return value;
  }
}

final class _FakeLearningClient implements BackendLearningActivityClient {
  final attachmentCalls =
      <
        ({
          int semesterId,
          int classId,
          int materialId,
          int attachmentId,
          int userId,
        })
      >[];
  final archiveCalls =
      <({int semesterId, int classId, int materialId, int userId})>[];

  @override
  Future<List<LearningMaterial>> getLearningMaterials({
    required int semesterId,
    required int classId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async => const [];

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachment({
    required int semesterId,
    required int classId,
    required int materialId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    attachmentCalls.add((
      semesterId: semesterId,
      classId: classId,
      materialId: materialId,
      attachmentId: attachmentId,
      userId: userId,
    ));
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      fileName: 'attachment.pdf',
      contentType: 'application/pdf',
    );
  }

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachmentArchive({
    required int semesterId,
    required int classId,
    required int materialId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    archiveCalls.add((
      semesterId: semesterId,
      classId: classId,
      materialId: materialId,
      userId: userId,
    ));
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [4, 5]),
      fileName: 'material-5001.zip',
      contentType: 'application/zip',
    );
  }
}

final class _RecordingSink implements AttachmentFileSink {
  final List<String> fileNames = [];

  @override
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    String? contentType,
    bool openAfterSave = true,
  }) async {
    fileNames.add(fileName);
    return '/saved/$fileName';
  }
}
