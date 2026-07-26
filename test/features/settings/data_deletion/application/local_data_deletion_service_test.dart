import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_ports.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';

void main() {
  test('delete all runs required steps in exact order', () async {
    final calls = <String>[];
    final harness = _Harness(calls);

    final result = await harness.service.deleteAll();

    expect(calls, [
      'beginOperationQuiescence',
      'background',
      'autostart',
      'notifications',
      'credentials',
      'scrubAll',
      'deleteFiles',
      'cache',
      'providerReset',
      'endOperationQuiescence',
    ]);
    expect(result.isComplete, isTrue);
    expect(result.steps.map((step) => step.step), LocalDataDeletionStep.values);
  });

  test('independent delete-all steps continue after failures', () async {
    final calls = <String>[];
    final harness = _Harness(
      calls,
      statuses: {
        'background': LocalDataDeletionStepStatus.failed,
        'autostart': LocalDataDeletionStepStatus.failed,
        'notifications': LocalDataDeletionStepStatus.failed,
        'credentials': LocalDataDeletionStepStatus.failed,
        'cache': LocalDataDeletionStepStatus.failed,
      },
    );

    final result = await harness.service.deleteAll();

    expect(
      calls,
      containsAll(<String>[
        'beginOperationQuiescence',
        'scrubAll',
        'deleteFiles',
        'providerReset',
        'endOperationQuiescence',
      ]),
    );
    expect(result.isComplete, isFalse);
    expect(
      result.failedSteps,
      containsAll(<LocalDataDeletionStep>[
        LocalDataDeletionStep.backgroundWork,
        LocalDataDeletionStep.desktopAutostart,
        LocalDataDeletionStep.notifications,
        LocalDataDeletionStep.credentials,
        LocalDataDeletionStep.cacheFiles,
      ]),
    );
  });

  test('failed logical scrub prevents unsafe physical deletion', () async {
    final calls = <String>[];
    final harness = _Harness(
      calls,
      statuses: {'scrubAll': LocalDataDeletionStepStatus.failed},
    );

    final result = await harness.service.deleteAll();

    expect(calls, isNot(contains('deleteFiles')));
    expect(
      calls,
      containsAllInOrder(<String>[
        'scrubAll',
        'cache',
        'endOperationQuiescence',
      ]),
    );
    expect(calls, isNot(contains('providerReset')));
    expect(
      result.failedSteps,
      containsAll(<LocalDataDeletionStep>[
        LocalDataDeletionStep.databaseContent,
        LocalDataDeletionStep.databaseFiles,
      ]),
    );
  });

  test('duplicate taps join the same in-flight operation', () async {
    final calls = <String>[];
    final blocker = Completer<void>();
    final harness = _Harness(calls, backgroundBlocker: blocker);

    final first = harness.service.deleteAll();
    final second = harness.service.deleteAll();
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(calls, ['beginOperationQuiescence', 'background']);
    blocker.complete();
    await Future.wait([first, second]);
    expect(calls.where((call) => call == 'background'), hasLength(1));
  });

  test('different operations are serialized', () async {
    final calls = <String>[];
    final blocker = Completer<void>();
    final harness = _Harness(calls, backgroundBlocker: blocker);

    final credentials = harness.service.deleteSavedCredentials();
    final cache = harness.service.deleteCachedAssignments();
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['beginOperationQuiescence', 'background']);
    blocker.complete();
    await Future.wait([credentials, cache]);
    expect(calls, [
      'beginOperationQuiescence',
      'background',
      'credentials',
      'expireSession',
      'endOperationQuiescence',
      'beginOperationQuiescence',
      'notifications',
      'deleteCachedAssignments',
      'endOperationQuiescence',
    ]);
  });

  test('each single action invokes only its intended scope', () async {
    final cacheCalls = <String>[];
    await _Harness(cacheCalls).service.deleteCachedAssignments();
    expect(cacheCalls, [
      'beginOperationQuiescence',
      'notifications',
      'deleteCachedAssignments',
      'endOperationQuiescence',
    ]);

    final credentialCalls = <String>[];
    await _Harness(credentialCalls).service.deleteSavedCredentials();
    expect(credentialCalls, [
      'beginOperationQuiescence',
      'background',
      'credentials',
      'expireSession',
      'endOperationQuiescence',
    ]);
  });

  test(
    'failed activity drain skips notification cancellation and is retryable',
    () async {
      final calls = <String>[];
      final statuses = <String, LocalDataDeletionStepStatus>{
        'beginOperationQuiescence': LocalDataDeletionStepStatus.failed,
        'endOperationQuiescence': LocalDataDeletionStepStatus.failed,
      };
      final harness = _Harness(calls, statuses: statuses);

      final first = await harness.service.deleteCachedAssignments();
      expect(first.isComplete, isFalse);
      expect(
        first.failedSteps,
        contains(LocalDataDeletionStep.activeOperations),
      );
      expect(first.failedSteps, contains(LocalDataDeletionStep.notifications));
      expect(calls, isNot(contains('notifications')));

      statuses['beginOperationQuiescence'] =
          LocalDataDeletionStepStatus.completed;
      statuses['endOperationQuiescence'] =
          LocalDataDeletionStepStatus.completed;
      final second = await harness.service.deleteCachedAssignments();

      expect(second.isComplete, isTrue);
      expect(calls.where((call) => call == 'notifications'), hasLength(1));
    },
  );

  test(
    'release failure downgrades the fixed active-operations result',
    () async {
      final harness = _Harness(
        <String>[],
        statuses: {
          'endOperationQuiescence': LocalDataDeletionStepStatus.failed,
        },
      );

      final result = await harness.service.deleteSavedCredentials();

      expect(result.isComplete, isFalse);
      expect(
        result.steps.first,
        const LocalDataDeletionStepResult(
          step: LocalDataDeletionStep.activeOperations,
          status: LocalDataDeletionStepStatus.failed,
        ),
      );
    },
  );

  test('retry after a partial failure runs a fresh operation', () async {
    final calls = <String>[];
    final statuses = <String, LocalDataDeletionStepStatus>{
      'credentials': LocalDataDeletionStepStatus.failed,
    };
    final harness = _Harness(calls, statuses: statuses);

    final first = await harness.service.deleteSavedCredentials();
    statuses['credentials'] = LocalDataDeletionStepStatus.completed;
    final second = await harness.service.deleteSavedCredentials();

    expect(first.isComplete, isFalse);
    expect(second.isComplete, isTrue);
    expect(calls.where((call) => call == 'credentials'), hasLength(2));
  });

  test('results and coordinator debug text stay bounded and redacted', () {
    const secret = '<SESSION_COOKIE>';
    final result = LocalDataDeletionResult(
      operation: LocalDataDeletionOperation.allLocalData,
      steps: const [
        LocalDataDeletionStepResult(
          step: LocalDataDeletionStep.credentials,
          status: LocalDataDeletionStepStatus.failed,
        ),
      ],
    );
    final coordinator = _Harness(<String>[]).service;

    for (final text in [
      result.toString(),
      result.steps.single.toString(),
      coordinator.toString(),
    ]) {
      expect(text, contains('redacted: true'));
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('/')));
    }
  });
}

final class _Harness {
  _Harness(
    this.calls, {
    Map<String, LocalDataDeletionStepStatus>? statuses,
    this.backgroundBlocker,
  }) : statuses = statuses ?? <String, LocalDataDeletionStepStatus>{} {
    service = LocalDataDeletionCoordinator(
      background: _Background(this),
      autostart: _Autostart(this),
      notifications: _Notifications(this),
      credentials: _Credentials(this),
      database: _Database(this),
      cache: _Cache(this),
      providerGraph: _ProviderReset(this),
    );
  }

  final List<String> calls;
  final Map<String, LocalDataDeletionStepStatus> statuses;
  final Completer<void>? backgroundBlocker;
  late final LocalDataDeletionCoordinator service;

  Future<LocalDataDeletionStepStatus> run(String name) async {
    calls.add(name);
    if (name == 'background') {
      await backgroundBlocker?.future;
    }
    return statuses[name] ?? LocalDataDeletionStepStatus.completed;
  }
}

final class _Background implements LocalDataBackgroundCleanup {
  _Background(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> cancel() => harness.run('background');
}

final class _Autostart implements LocalDataAutostartCleanup {
  _Autostart(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> disable() => harness.run('autostart');
}

final class _Notifications implements LocalDataNotificationCleanup {
  _Notifications(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> cancelAll() =>
      harness.run('notifications');
}

final class _Credentials implements LocalDataCredentialCleanup {
  _Credentials(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> clear() => harness.run('credentials');
}

final class _Database implements LocalDataDatabaseCleanup {
  _Database(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> beginOperationQuiescence() =>
      harness.run('beginOperationQuiescence');
  @override
  Future<LocalDataDeletionStepStatus> deleteCachedAssignments() =>
      harness.run('deleteCachedAssignments');
  @override
  Future<LocalDataDeletionStepStatus> deleteFiles() =>
      harness.run('deleteFiles');
  @override
  Future<LocalDataDeletionStepStatus> expireSession() =>
      harness.run('expireSession');
  @override
  Future<LocalDataDeletionStepStatus> scrubAll() => harness.run('scrubAll');
  @override
  Future<LocalDataDeletionStepStatus> endOperationQuiescence() =>
      harness.run('endOperationQuiescence');
}

final class _Cache implements LocalApplicationCacheCleanup {
  _Cache(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> clear() => harness.run('cache');
}

final class _ProviderReset implements LocalProviderGraphReset {
  _ProviderReset(this.harness);
  final _Harness harness;
  @override
  Future<LocalDataDeletionStepStatus> reset() => harness.run('providerReset');
}
