final class NewAssignmentNotificationSettings {
  const NewAssignmentNotificationSettings({required this.enabled});

  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is NewAssignmentNotificationSettings && other.enabled == enabled;

  @override
  int get hashCode => enabled.hashCode;

  @override
  String toString() => 'NewAssignmentNotificationSettings(redacted: true)';
}
