import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_refresh_status_bridge.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_workmanager_scheduler_platform.dart';
import 'package:leb2_watch/src/platform/background/workmanager/workmanager_gateway.dart';

void main() {
  test('initialization is joined and retains the iOS dispatcher', () async {
    final gateway = _Gateway();
    final platform = IosWorkmanagerSchedulerPlatform(
      gateway,
      const _StatusBridge(),
    );

    await Future.wait([platform.initialize(), platform.initialize()]);

    expect(gateway.initializeCalls, 1);
    expect(gateway.callbackDispatcher, isNotNull);
  });

  test('schedule submits one stable best-effort iOS contract', () async {
    final gateway = _Gateway();
    final platform = IosWorkmanagerSchedulerPlatform(
      gateway,
      const _StatusBridge(),
    );

    await platform.schedulePeriodicSync(
      cadence: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 3, seconds: 4),
    );
    await platform.schedulePeriodicSync(
      cadence: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 3, seconds: 4),
    );

    expect(gateway.requests, hasLength(2));
    for (final request in gateway.requests) {
      expect(request.uniqueName, iosAssignmentRefreshTaskIdentifier);
      expect(request.taskName, iosAssignmentRefreshTaskIdentifier);
      expect(request.frequency, const Duration(minutes: 15));
      expect(request.initialDelay, const Duration(minutes: 3, seconds: 4));
      expect(request.inputData, isNull);
      expect(request.tag, isNull);
      expect(request.networkRequirement, WorkmanagerNetworkRequirement.none);
      expect(request.existingPolicy, WorkmanagerPeriodicWorkPolicy.update);
    }
  });

  test('cancel and status use only exact iOS native contracts', () async {
    final gateway = _Gateway();
    final pending = IosWorkmanagerSchedulerPlatform(
      gateway,
      const _StatusBridge(pending: true),
    );
    final inactive = IosWorkmanagerSchedulerPlatform(
      gateway,
      const _StatusBridge(),
    );
    final denied = IosWorkmanagerSchedulerPlatform(
      gateway,
      const _StatusBridge(
        availability: IosBackgroundRefreshAvailability.denied,
      ),
    );

    expect(
      await pending.getStatus(),
      const BackgroundScheduleActive(approximateNextCheckAtUtc: null),
    );
    expect(await inactive.getStatus(), const BackgroundScheduleInactive());
    expect(
      await denied.getStatus(),
      const BackgroundScheduleUnavailable(
        BackgroundScheduleUnavailableReason.registrationFailed,
      ),
    );
    await pending.cancelPeriodicSync();

    expect(gateway.cancelNames, [iosAssignmentRefreshTaskIdentifier]);
    expect(gateway.statusCalls, 0);
  });
}

final class _Gateway implements WorkmanagerGateway {
  int initializeCalls = 0;
  int statusCalls = 0;
  WorkmanagerCallbackDispatcher? callbackDispatcher;
  final List<WorkmanagerPeriodicTaskRequest> requests = [];
  final List<String> cancelNames = [];

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
  }

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async {
    statusCalls += 1;
    throw UnsupportedError('iOS does not expose this Workmanager API');
  }

  @override
  Future<void> registerPeriodicTask(
    WorkmanagerPeriodicTaskRequest request,
  ) async {
    requests.add(request);
  }

  @override
  Future<void> registerOneOffTask(WorkmanagerOneOffTaskRequest request) async {}
}

final class _StatusBridge implements IosBackgroundRefreshStatusBridge {
  const _StatusBridge({
    this.availability = IosBackgroundRefreshAvailability.available,
    this.pending = false,
  });

  final IosBackgroundRefreshAvailability availability;
  final bool pending;

  @override
  Future<IosBackgroundRefreshSnapshot> readStatus() async {
    return IosBackgroundRefreshSnapshot(
      availability: availability,
      pending: pending,
    );
  }
}
