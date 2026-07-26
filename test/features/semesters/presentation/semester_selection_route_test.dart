import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/features/semesters/presentation/semester_selection_route.dart';

void main() {
  for (final testCase in [
    (
      description: 'missing backend configuration',
      configuration: AppConfiguration.parse(),
      sourceValue: '',
    ),
    (
      description: 'malformed backend configuration',
      configuration: AppConfiguration.parse(backendBaseUrl: 'relative/path'),
      sourceValue: 'relative/path',
    ),
  ]) {
    testWidgets(
      '${testCase.description} preserves the production cached route',
      (tester) async {
        final database = await _seedDatabase(
          semesterIds: const [202, 101],
          sessionLifecycle: 'active',
        );
        addTearDown(database.close);

        await tester.pumpWidget(
          _ProductionRouteHarness(
            database: database,
            configuration: testCase.configuration,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Semester 202'), findsOneWidget);
        expect(find.text('Semester 101'), findsOneWidget);
        expect(find.text('Semester selection unavailable'), findsNothing);
        expect(find.byKey(const Key('semester-stale-banner')), findsOneWidget);
        expect(
          find.textContaining('BackendApiConfigurationException'),
          findsNothing,
        );
        if (testCase.sourceValue.isNotEmpty) {
          expect(find.textContaining(testCase.sourceValue), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('expired cached route never resolves the backend provider', (
    tester,
  ) async {
    final database = await _seedDatabase(
      semesterIds: const [303, 202],
      sessionLifecycle: 'expired',
    );
    addTearDown(database.close);
    var backendProviderResolutions = 0;

    await tester.pumpWidget(
      _ProductionRouteHarness(
        database: database,
        configuration: AppConfiguration.parse(),
        backendClientFactory: () {
          backendProviderResolutions += 1;
          throw StateError('The backend provider must stay unresolved.');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Semester 303'), findsOneWidget);
    expect(find.text('Semester 202'), findsOneWidget);
    expect(find.byKey(const Key('semester-session-expired')), findsOneWidget);
    expect(find.text('Semester selection unavailable'), findsNothing);
    expect(backendProviderResolutions, 0);

    await tester.tap(find.byKey(const Key('semester-refresh-button')));
    await tester.pumpAndSettle();

    expect(backendProviderResolutions, 0);
    expect(find.byKey(const Key('semester-session-expired')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _ProductionRouteHarness extends StatelessWidget {
  const _ProductionRouteHarness({
    required this.database,
    required this.configuration,
    this.backendClientFactory,
  });

  final AppDatabase database;
  final AppConfiguration configuration;
  final BackendApiClient Function()? backendClientFactory;

  @override
  Widget build(BuildContext context) {
    final factory = backendClientFactory;
    return ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        appDatabaseProvider.overrideWith((_) async => database),
        if (factory != null)
          backendApiClientProvider.overrideWith((_) => factory()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const SemesterSelectionRoute(),
      ),
    );
  }
}

Future<AppDatabase> _seedDatabase({
  required Iterable<int> semesterIds,
  required String sessionLifecycle,
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  for (final semesterId in semesterIds) {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: drift.Value(semesterId)));
  }
  await database
      .into(database.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          singletonId: const drift.Value(1),
          leb2UserId: const drift.Value(2001),
          sessionLifecycle: drift.Value(sessionLifecycle),
          sessionRevision: const drift.Value(4),
        ),
      );
  return database;
}
