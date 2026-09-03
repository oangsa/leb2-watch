const sanitizedSemestersFixture = <Map<String, Object?>>[
  {'id': 101, 'name': '1/2026'},
  {'id': 102, 'name': '3/2025'},
];

const sanitizedCredentialsRequest = <String, Object?>{
  'username': '<USERNAME>',
  'password': '<PASSWORD>',
  'remember': false,
};

const sanitizedUserProfileFixture = <String, Object?>{
  'id': 2001,
  'kmuttId': '<KMUTT_ID>',
  'nameThai': '<THAI_NAME>',
  'nameEnglish': '<ENGLISH_NAME>',
  'surnameThai': '<THAI_SURNAME>',
  'surnameEnglish': '<ENGLISH_SURNAME>',
};

Map<String, Object?> sanitizedCookieFixture(String cookie) {
  return <String, Object?>{'cookie': cookie};
}

const sanitizedBaselineActivity = <String, Object?>{
  'id': 1001,
  'userId': 2001,
  'classId': 3001,
  'advStarred': 0,
  'groupType': 'individual',
  'type': 'ASM',
  'peerAssessment': 0,
  'isAllowRepeat': 0,
  'title': 'Example assignment',
  'description': '<p>Example description</p>',
  'startDate': '2026-07-01T02:00:00.000Z',
  'dueDate': '2026-07-31T16:59:00.000Z',
  'editGroupMode': '',
  'createdAt': '2026-06-30T05:00:00.000Z',
  'user': 2001,
  'activitySubmissionId': null,
  'classUserId': 4001,
  'activityGroupId': null,
  'activityGroupName': null,
  'activitySubmissionSubmittedAt': null,
  'dueDateExceed': false,
  'quizSubmissionIsSubmitted': false,
  'countGroupMember': 1,
  'activitySubmissionIsLate': false,
  'fileActivities': <Object?>[],
  'questions': <Object?>[],
  'submissions': <Object?>[],
  'lastDueDateNotificationDate': null,
  'lastStatusChangeNotificationDate': null,
  'previousSubmissionStatus': null,
};

const sanitizedNewActivity = <String, Object?>{
  'id': 1002,
  'userId': 2001,
  'classId': 3001,
  'advStarred': 0,
  'groupType': 'individual',
  'type': 'ASM',
  'peerAssessment': 0,
  'isAllowRepeat': 0,
  'title': 'New example assignment',
  'description': '<p>Sanitized new assignment description</p>',
  'startDate': '2026-07-25T02:00:00.000Z',
  'dueDate': '2026-08-15T16:59:00.000Z',
  'editGroupMode': '',
  'createdAt': '2026-07-25T01:00:00.000Z',
  'user': 2001,
  'activitySubmissionId': null,
  'classUserId': 4002,
  'activityGroupId': null,
  'activityGroupName': null,
  'activitySubmissionSubmittedAt': null,
  'dueDateExceed': false,
  'quizSubmissionIsSubmitted': false,
  'countGroupMember': 1,
  'activitySubmissionIsLate': false,
  'fileActivities': <Object?>[],
  'questions': <Object?>[],
  'submissions': <Object?>[],
  'lastDueDateNotificationDate': null,
  'lastStatusChangeNotificationDate': null,
  'previousSubmissionStatus': null,
};

/// The recorded snapshot body.
///
/// [newAssignmentDueDateUtc] replaces the new assignment's recorded deadline.
/// The capture pins a fixed instant, so a test that needs the deadline to
/// still be ahead of the run's clock — deadline reminders are only placed for
/// future instants — has to rebase it rather than inherit an expiring date.
Map<String, Object?> sanitizedSnapshotFixture({
  required bool includeNewAssignment,
  DateTime? newAssignmentDueDateUtc,
}) {
  return <String, Object?>{
    'semesterId': 101,
    'classes': <Object?>[
      <String, Object?>{
        'id': 3001,
        'name': 'Example Course',
        'activities': <Object?>[
          sanitizedBaselineActivity,
          if (includeNewAssignment)
            <String, Object?>{
              ...sanitizedNewActivity,
              if (newAssignmentDueDateUtc != null)
                'dueDate': newAssignmentDueDateUtc.toIso8601String(),
            },
        ],
      },
      <String, Object?>{
        'id': 3002,
        'name': 'Course Without Activities',
        'activities': <Object?>[],
      },
    ],
  };
}

const sanitizedSessionExpiredFixture = <String, Object?>{
  'message': 'The LEB2 session has expired or is invalid.',
  'responseCode': 'SESSION_EXPIRED',
  'details': null,
  'timestamp': '2026-07-24T12:00:00Z',
  'traceId': '<TRACE_ID>',
};
