enum AssignmentSubmissionStatus { submitted, unsubmitted, notApplicable }

/// Resolves the saved submission state the dashboard and the detail view both
/// read.
///
/// The rule lives here so the two views cannot drift apart. LEB2 reports quiz
/// submission on its own field rather than through a submission record, and an
/// activity saved without a deadline has nothing to submit against.
///
/// `hasSubmissionRecord` is passed as a decided boolean rather than the stored
/// submission JSON: the backend does not fix that object's internal fields, so
/// only its presence is contractual.
AssignmentSubmissionStatus resolveAssignmentSubmissionStatus({
  required String activityType,
  required String? dueDateSource,
  required bool hasSubmissionRecord,
  required bool quizSubmissionIsSubmitted,
}) {
  if (activityType == 'QUZ') {
    return quizSubmissionIsSubmitted
        ? AssignmentSubmissionStatus.submitted
        : AssignmentSubmissionStatus.unsubmitted;
  }
  if (hasSubmissionRecord) {
    return AssignmentSubmissionStatus.submitted;
  }
  return dueDateSource == null
      ? AssignmentSubmissionStatus.notApplicable
      : AssignmentSubmissionStatus.unsubmitted;
}
