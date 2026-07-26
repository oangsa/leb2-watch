final class DeadlineReminderSchedulingPolicy {
  const DeadlineReminderSchedulingPolicy({
    required this.supportsScheduling,
    required this.supportsCancellation,
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
    maximumPendingCount: null,
  );
  static const unsupported = DeadlineReminderSchedulingPolicy(
    supportsScheduling: false,
    supportsCancellation: false,
    maximumPendingCount: null,
  );

  final bool supportsScheduling;
  final bool supportsCancellation;
  final int? maximumPendingCount;

  @override
  bool operator ==(Object other) =>
      other is DeadlineReminderSchedulingPolicy &&
      other.supportsScheduling == supportsScheduling &&
      other.supportsCancellation == supportsCancellation &&
      other.maximumPendingCount == maximumPendingCount;

  @override
  int get hashCode => Object.hash(
    supportsScheduling,
    supportsCancellation,
    maximumPendingCount,
  );

  @override
  String toString() => 'DeadlineReminderSchedulingPolicy(redacted: true)';
}
