import 'dart:collection';

enum DeadlineReminderOffset {
  oneHour(minutes: 60),
  twentyFourHours(minutes: 1440);

  const DeadlineReminderOffset({required this.minutes});

  final int minutes;
}

final class DeadlineReminderPreferences {
  DeadlineReminderPreferences({
    required this.enabled,
    required Set<DeadlineReminderOffset> offsets,
  }) : offsets = UnmodifiableSetView(Set.of(offsets));

  const DeadlineReminderPreferences._({
    required this.enabled,
    required this.offsets,
  });

  static const defaults = DeadlineReminderPreferences._(
    enabled: true,
    offsets: {
      DeadlineReminderOffset.oneHour,
      DeadlineReminderOffset.twentyFourHours,
    },
  );

  final bool enabled;
  final Set<DeadlineReminderOffset> offsets;

  DeadlineReminderPreferences copyWith({
    bool? enabled,
    Set<DeadlineReminderOffset>? offsets,
  }) {
    return DeadlineReminderPreferences(
      enabled: enabled ?? this.enabled,
      offsets: offsets ?? this.offsets,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeadlineReminderPreferences &&
      other.enabled == enabled &&
      other.offsets.length == offsets.length &&
      other.offsets.containsAll(offsets);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAllUnordered(offsets));

  @override
  String toString() => 'DeadlineReminderPreferences(redacted: true)';
}
