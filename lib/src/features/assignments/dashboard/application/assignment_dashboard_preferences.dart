enum AssignmentDashboardSection { recent, overdue, all }

enum AssignmentSubmissionFilter { all, unsubmitted }

final class AssignmentDashboardPreferences {
  const AssignmentDashboardPreferences({
    this.section = AssignmentDashboardSection.all,
    this.searchQuery = '',
    this.selectedCourseId,
    this.submissionFilter = AssignmentSubmissionFilter.unsubmitted,
    this.deadlineAtOrBeforeBangkok,
  }) : assert(selectedCourseId == null || selectedCourseId > 0);

  final AssignmentDashboardSection section;
  final String searchQuery;
  final int? selectedCourseId;
  final AssignmentSubmissionFilter submissionFilter;
  final DateTime? deadlineAtOrBeforeBangkok;

  @override
  bool operator ==(Object other) =>
      other is AssignmentDashboardPreferences &&
      other.section == section &&
      other.searchQuery == searchQuery &&
      other.selectedCourseId == selectedCourseId &&
      other.submissionFilter == submissionFilter &&
      other.deadlineAtOrBeforeBangkok == deadlineAtOrBeforeBangkok;

  @override
  int get hashCode => Object.hash(
    section,
    searchQuery,
    selectedCourseId,
    submissionFilter,
    deadlineAtOrBeforeBangkok,
  );

  @override
  String toString() => 'AssignmentDashboardPreferences(redacted: true)';
}
