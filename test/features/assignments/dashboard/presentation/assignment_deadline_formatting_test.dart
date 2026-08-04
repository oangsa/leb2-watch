import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_projection.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/presentation/assignment_dashboard_page.dart';

void main() {
  testWidgets('every deadline shape renders as readable GMT+7 wall time', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // A zoned deadline is an instant and must be shifted into GMT+7.
    expect(
      formatAssignmentDeadline(
        context,
        AssignmentDeadline.fromSource('2026-01-19T00:00:59-05:00'),
      ),
      'Mon, Jan 19, 12:00 PM GMT+7',
    );

    // An unzoned deadline is already Bangkok wall time, so its components
    // render directly instead of being shifted a second time.
    expect(
      formatAssignmentDeadline(
        context,
        AssignmentDeadline.fromSource('2026-01-19T12:00:59'),
      ),
      'Mon, Jan 19, 12:00 PM GMT+7',
    );

    expect(
      formatAssignmentDeadline(context, AssignmentDeadline.fromSource(null)),
      'No deadline',
    );
    expect(
      formatAssignmentDeadline(
        context,
        AssignmentDeadline.fromSource('not a date'),
      ),
      'Deadline unavailable',
    );
  });

  testWidgets('sync timestamps render in GMT+7, not the device time zone', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      formatAssignmentTimestamp(context, DateTime.utc(2026, 8, 3, 5, 23)),
      'Mon, Aug 3, 12:23 PM GMT+7',
    );
  });
}
