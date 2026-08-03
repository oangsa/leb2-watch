import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/presentation/local_data_deletion_panel.dart';

void main() {
  testWidgets('shows three explicit destructive actions and confirmations', (
    tester,
  ) async {
    await _pump(tester, _DeletionService());

    expect(find.byKey(const Key('delete-cached-assignments')), findsOneWidget);
    expect(find.byKey(const Key('delete-saved-credentials')), findsOneWidget);
    expect(find.byKey(const Key('delete-all-local-data')), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-cached-assignments')));
    await tester.pumpAndSettle();
    expect(find.text('Delete cached assignments?'), findsOneWidget);
    expect(find.textContaining('Credentials and global preferences'), findsOne);
    await tester.tap(find.byKey(const Key('cancel-local-data-deletion')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-saved-credentials')));
    await tester.pumpAndSettle();
    expect(find.text('Delete saved credentials?'), findsOneWidget);
    expect(find.textContaining('Cached assignments will remain'), findsOne);
    await tester.tap(find.byKey(const Key('cancel-local-data-deletion')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-all-local-data')));
    await tester.pumpAndSettle();
    expect(find.text('Delete all local data?'), findsOneWidget);
    expect(find.textContaining('you will stay here and can retry'), findsOne);
  });

  testWidgets(
    'progress blocks duplicate activation and complete result routes',
    (tester) async {
      final completion = Completer<LocalDataDeletionResult>();
      final service = _DeletionService(allResult: completion.future);
      final completed = <LocalDataDeletionOperation>[];
      await _pump(tester, service, onCompleted: completed.add);

      await tester.tap(find.byKey(const Key('delete-all-local-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-local-data-deletion')));
      await tester.pump();

      expect(find.byKey(const Key('local-data-deletion-progress')), findsOne);
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('delete-all-local-data')))
            .enabled,
        isFalse,
      );
      expect(service.allCalls, 1);

      completion.complete(_complete(LocalDataDeletionOperation.allLocalData));
      await tester.pumpAndSettle();
      expect(completed, [LocalDataDeletionOperation.allLocalData]);
    },
  );

  testWidgets('partial result stays bounded and retries the same operation', (
    tester,
  ) async {
    final service = _DeletionService(
      credentialResults: [
        _failed(
          LocalDataDeletionOperation.savedCredentials,
          LocalDataDeletionStep.credentials,
        ),
        _complete(LocalDataDeletionOperation.savedCredentials),
      ],
    );
    final completed = <LocalDataDeletionOperation>[];
    await _pump(tester, service, onCompleted: completed.add);

    await tester.tap(find.byKey(const Key('delete-saved-credentials')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-local-data-deletion')));
    await tester.pumpAndSettle();

    expect(find.text('Some local data could not be removed.'), findsOne);
    expect(find.textContaining('secure credentials'), findsOne);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('/home/'), findsNothing);
    expect(completed, isEmpty);

    await tester.tap(find.byKey(const Key('retry-local-data-deletion')));
    await tester.pumpAndSettle();
    expect(service.credentialCalls, 2);
    expect(completed, [LocalDataDeletionOperation.savedCredentials]);
  });

  testWidgets('remains usable at compact width and 200 percent text', (
    tester,
  ) async {
    await _pump(
      tester,
      _DeletionService(),
      width: 320,
      height: 640,
      textScaler: const TextScaler.linear(2),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('delete-all-local-data')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('delete-all-local-data')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  LocalDataDeletionService service, {
  ValueChanged<LocalDataDeletionOperation>? onCompleted,
  double width = 800,
  double height = 900,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height), textScaler: textScaler),
        child: Scaffold(
          body: ListView(
            children: [
              LocalDataDeletionPanel(
                service: service,
                onCompleted: onCompleted ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LocalDataDeletionResult _complete(LocalDataDeletionOperation operation) {
  return LocalDataDeletionResult(operation: operation, steps: const []);
}

LocalDataDeletionResult _failed(
  LocalDataDeletionOperation operation,
  LocalDataDeletionStep step,
) {
  return LocalDataDeletionResult(
    operation: operation,
    steps: [
      LocalDataDeletionStepResult(
        step: step,
        status: LocalDataDeletionStepStatus.failed,
      ),
    ],
  );
}

final class _DeletionService implements LocalDataDeletionService {
  _DeletionService({
    this.allResult,
    List<LocalDataDeletionResult>? credentialResults,
  }) : credentialResults = credentialResults ?? [];

  final Future<LocalDataDeletionResult>? allResult;
  final List<LocalDataDeletionResult> credentialResults;
  int allCalls = 0;
  int credentialCalls = 0;

  @override
  Future<LocalDataDeletionResult> deleteAll() {
    allCalls += 1;
    return allResult ??
        Future.value(_complete(LocalDataDeletionOperation.allLocalData));
  }

  @override
  Future<LocalDataDeletionResult> deleteCachedAssignments() async =>
      _complete(LocalDataDeletionOperation.cachedAssignments);

  @override
  Future<LocalDataDeletionResult> deleteSavedCredentials() async {
    final result = credentialResults[credentialCalls];
    credentialCalls += 1;
    return result;
  }
}
