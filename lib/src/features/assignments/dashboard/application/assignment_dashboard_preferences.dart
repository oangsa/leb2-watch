enum AssignmentDashboardSection { recent, overdue, all }

enum AssignmentSubmissionFilter { all, unsubmitted }

enum AssignmentStarredFilter { all, starred }

final class AssignmentDashboardPreferences {
  const AssignmentDashboardPreferences({
    this.section = AssignmentDashboardSection.all,
    this.searchQuery = '',
    this.selectedCourseId,
    this.submissionFilter = AssignmentSubmissionFilter.unsubmitted,
    this.starredFilter = AssignmentStarredFilter.all,
    this.deadlineAtOrBeforeBangkok,
  }) : assert(selectedCourseId == null || selectedCourseId > 0);

  final AssignmentDashboardSection section;
  final String searchQuery;
  final int? selectedCourseId;
  final AssignmentSubmissionFilter submissionFilter;
  final AssignmentStarredFilter starredFilter;
  final DateTime? deadlineAtOrBeforeBangkok;

  @override
  bool operator ==(Object other) =>
      other is AssignmentDashboardPreferences &&
      other.section == section &&
      other.searchQuery == searchQuery &&
      other.selectedCourseId == selectedCourseId &&
      other.submissionFilter == submissionFilter &&
      other.starredFilter == starredFilter &&
      other.deadlineAtOrBeforeBangkok == deadlineAtOrBeforeBangkok;

  @override
  int get hashCode => Object.hash(
    section,
    searchQuery,
    selectedCourseId,
    submissionFilter,
    starredFilter,
    deadlineAtOrBeforeBangkok,
  );

  @override
  String toString() => 'AssignmentDashboardPreferences(redacted: true)';
}
