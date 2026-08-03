import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/authentication/application/logout_service.dart';
import 'package:leb2_watch/src/features/settings/session/logout_panel.dart';

void main() {
  testWidgets('confirms logout and navigates only after service success', (
    tester,
  ) async {
    var calls = 0;
    var completed = 0;
    final service = _FakeLogoutService(() {
      calls += 1;
      return const LogoutSuccess();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogoutPanel(
            service: service,
            onCompleted: () => completed += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logout-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-logout')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-logout-action')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(completed, 1);
  });

  testWidgets('shows device mismatch without invoking completion', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogoutPanel(
            service: _FakeLogoutService(
              () => const LogoutFailure(LogoutFailureKind.deviceMismatch),
            ),
            onCompleted: () => completed += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logout-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-logout-action')));
    await tester.pumpAndSettle();

    expect(find.textContaining('bound to another device'), findsOneWidget);
    expect(completed, 0);
  });
}

final class _FakeLogoutService implements LogoutService {
  _FakeLogoutService(this.callback);

  final LogoutResult Function() callback;

  @override
  Future<LogoutResult> logout() async => callback();
}
