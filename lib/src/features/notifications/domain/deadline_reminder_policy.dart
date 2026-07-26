final class DeadlineReminderSchedulingPolicy {
  const DeadlineReminderSchedulingPolicy({
    required this.supportsScheduling,
    required this.supportsCancellation,
    this.supportsProcessLifetimeDelivery = false,
    required this.maximumPendingCount,
  }) : assert(
         maximumPendingCount == null || maximumPendingCount > 0,
         'Maximum pending count must be positive.',
       );

  static const android = DeadlineReminderSchedulingPolicy(
    supportsScheduling: true,
    supportsCancellation: true,
    maximumPendingCount: null,
  );
  static const iOS = DeadlineReminderSchedulingPolicy(
    supportsScheduling: true,
    supportsCancellation: true,
    maximumPendingCount: 64,
  );
  static const macOS = DeadlineReminderSchedulingPolicy(
    supportsScheduling: true,
    supportsCancellation: true,
    maximumPendingCount: null,
  );
  static const linux = DeadlineReminderSchedulingPolicy(
    supportsScheduling: false,
    supportsCancellation: true,
    supportsProcessLifetimeDelivery: true,
    maximumPendingCount: null,
  );
  static const windowsPackaged = DeadlineReminderSchedulingPolicy(
    supportsScheduling: true,
    supportsCancellation: true,
    maximumPendingCount: null,
  );
  static const windowsUnpackaged = DeadlineReminderSchedulingPolicy(
    supportsScheduling: false,
    supportsCancellation: false,
    supportsProcessLifetimeDelivery: true,
    maximumPendingCount: null,
  );
  static const unsupported = DeadlineReminderSchedulingPolicy(
    supportsScheduling: false,
    supportsCancellation: false,
    maximumPendingCount: null,
  );

  final bool supportsScheduling;
  final bool supportsCancellation;
  final bool supportsProcessLifetimeDelivery;
  final int? maximumPendingCount;

  @override
  bool operator ==(Object other) =>
      other is DeadlineReminderSchedulingPolicy &&
      other.supportsScheduling == supportsScheduling &&
      other.supportsCancellation == supportsCancellation &&
      other.supportsProcessLifetimeDelivery ==
          supportsProcessLifetimeDelivery &&
      other.maximumPendingCount == maximumPendingCount;

  @override
  int get hashCode => Object.hash(
    supportsScheduling,
    supportsCancellation,
    supportsProcessLifetimeDelivery,
    maximumPendingCount,
  );

  @override
  String toString() => 'DeadlineReminderSchedulingPolicy(redacted: true)';
}
