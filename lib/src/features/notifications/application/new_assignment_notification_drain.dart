import '../../semesters/data/semester_selection_store.dart';
import 'new_assignment_notification_coordinator.dart';

abstract interface class NewAssignmentNotificationDrain {
  Future<void> drainActiveCached();
}

final class ActiveSemesterNewAssignmentNotificationDrain
    implements NewAssignmentNotificationDrain {
  const ActiveSemesterNewAssignmentNotificationDrain(
    this._semesters,
    this._coordinator,
  );

  final SemesterSelectionStore _semesters;
  final NewAssignmentNotificationCoordinator _coordinator;

  @override
  Future<void> drainActiveCached() async {
    final semesterId = (await _semesters.read()).activeSemesterId;
    if (semesterId == null) {
      return;
    }
    await _coordinator.processCachedPending(semesterId: semesterId);
  }

  @override
  String toString() =>
      'ActiveSemesterNewAssignmentNotificationDrain(redacted: true)';
}
