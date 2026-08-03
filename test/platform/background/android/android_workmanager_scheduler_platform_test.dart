import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/platform/background/android/android_workmanager_scheduler_platform.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_gateway.dart';

void main() {
  test('initialization is joined and uses the retained callback', () async {
    final gateway = _Gateway();
    final platform = AndroidWorkmanagerSchedulerPlatform(gateway);

    await Future.wait([platform.initialize(), platform.initialize()]);

    expect(gateway.initializeCalls, 1);
    expect(gateway.callbackDispatcher, isNotNull);
  });

  test(
    'failed initialization can be retried without leaking details',
    () async {
      final gateway = _Gateway()..initializeFailures = 1;
      final platform = AndroidWorkmanagerSchedulerPlatform(gateway);

      await expectLater(platform.initialize(), throwsStateError);
      await platform.initialize();

      expect(gateway.initializeCalls, 2);
      expect(platform.toString(), isNot(contains('PRIVATE_PATH')));
    },
  );

  test('periodic schedule uses the one stable Android work contract', () async {
    final gateway = _Gateway();
    final tokens = <String>[
      '000102030405060708090a0b0c0d0e0f',
      'f0e0d0c0b0a090807060504030201000',
    ].iterator;
    final platform = AndroidWorkmanagerSchedulerPlatform(gateway, () {
      tokens.moveNext();
      return tokens.current;
    });
    const jitter = Duration(minutes: 4, seconds: 12);

    await platform.schedulePeriodicSync(
      cadence: const Duration(minutes: 15),
      initialDelay: jitter,
    );
    await platform.schedulePeriodicSync(
      cadence: const Duration(minutes: 15),
      initialDelay: jitter,
    );

    expect(gateway.requests, hasLength(2));
    for (var index = 0; index < gateway.requests.length; index += 1) {
      final request = gateway.requests[index];
      final expectedTag =
          '$androidPeriodicSyncGenerationTagPrefix${['000102030405060708090a0b0c0d0e0f', 'f0e0d0c0b0a090807060504030201000'][index]}';
      expect(request.uniqueName, androidPeriodicSyncUniqueWorkName);
      expect(request.taskName, androidPeriodicSyncTaskName);
      expect(request.tag, expectedTag);
      expect(request.inputData, {
        androidPeriodicSyncGenerationInputKey: expectedTag,
      });
      expect(request.inputData, hasLength(1));
      expect(request.toString(), isNot(contains(expectedTag)));
      expect(request.frequency, const Duration(minutes: 15));
      expect(request.initialDelay, jitter);
      expect(
        request.networkRequirement,
        WorkmanagerNetworkRequirement.connected,
      );
      expect(request.existingPolicy, WorkmanagerPeriodicWorkPolicy.update);
    }
    expect(gateway.requests[0].tag, isNot(gateway.requests[1].tag));
  });

  test(
    'default source creates a strict opaque 128-bit generation tag',
    () async {
      final gateway = _Gateway();
      final platform = AndroidWorkmanagerSchedulerPlatform(gateway);

      await platform.schedulePeriodicSync(
        cadence: const Duration(minutes: 15),
        initialDelay: Duration.zero,
      );

      final request = gateway.requests.single;
      final generationTag = request.tag;
      expect(generationTag, isNotNull);
      expect(
        generationTag,
        hasLength(androidPeriodicSyncGenerationTagPrefix.length + 32),
      );
      expect(
        parseAndroidPeriodicSyncGenerationTag(generationTag),
        generationTag,
      );
      expect(request.inputData, {
        androidPeriodicSyncGenerationInputKey: generationTag,
      });
    },
  );

  test('invalid generated token is rejected before registration', () async {
    final gateway = _Gateway();
    final platform = AndroidWorkmanagerSchedulerPlatform(
      gateway,
      () => 'USER_OR_SESSION_VALUE',
    );

    Object? error;
    try {
      await platform.schedulePeriodicSync(
        cadence: const Duration(minutes: 15),
        initialDelay: Duration.zero,
      );
    } on Object catch (caught) {
      error = caught;
    }

    expect(error, isA<ArgumentError>());
    expect(error.toString(), isNot(contains('USER_OR_SESSION_VALUE')));
    expect(gateway.requests, isEmpty);
  });

  test('cadence below WorkManager minimum is rejected before registration', () {
    final gateway = _Gateway();
    final platform = AndroidWorkmanagerSchedulerPlatform(gateway);

    expect(
      () => platform.schedulePeriodicSync(
        cadence: const Duration(minutes: 14, seconds: 59),
        initialDelay: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(gateway.requests, isEmpty);
  });

  test('cancel and status are scoped to the one unique work name', () async {
    final gateway = _Gateway()..scheduled = true;
    final platform = AndroidWorkmanagerSchedulerPlatform(gateway);

    expect(await platform.getStatus(), isA<BackgroundScheduleActive>());
    await platform.cancelPeriodicSync();
    await platform.cancelPeriodicSync();
    gateway.scheduled = false;
    expect(await platform.getStatus(), const BackgroundScheduleInactive());

    expect(gateway.statusNames, [
      androidPeriodicSyncUniqueWorkName,
      androidPeriodicSyncUniqueWorkName,
    ]);
    expect(gateway.cancelNames, [
      androidPeriodicSyncUniqueWorkName,
      androidPeriodicSyncUniqueWorkName,
    ]);
  });
}

final class _Gateway implements WorkmanagerGateway {
  int initializeCalls = 0;
  WorkmanagerCallbackDispatcher? callbackDispatcher;
  final List<WorkmanagerPeriodicTaskRequest> requests = [];
  final List<String> cancelNames = [];
  final List<String> statusNames = [];
  bool scheduled = false;
  int initializeFailures = 0;

  @override
  void bindTaskHandler(WorkmanagerPluginTaskHandler handler) {}

  @override
  Future<void> cancelByTag(String tag) async {}

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelNames.add(uniqueName);
  }

  @override
  Future<void> initialize(WorkmanagerCallbackDispatcher dispatcher) async {
    initializeCalls += 1;
    callbackDispatcher = dispatcher;
    if (initializeFailures > 0) {
      initializeFailures -= 1;
      throw StateError('PRIVATE_PATH');
    }
  }

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async {
    statusNames.add(uniqueName);
    return scheduled;
  }

  @override
  Future<void> registerPeriodicTask(
    WorkmanagerPeriodicTaskRequest request,
  ) async {
    requests.add(request);
  }
}
