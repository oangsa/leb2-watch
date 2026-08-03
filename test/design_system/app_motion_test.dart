import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_motion.dart';

void main() {
  testWidgets('preserves named duration when animations are enabled', (
    tester,
  ) async {
    Duration? resolved;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            resolved = AppMotion.resolve(context, AppMotion.standard);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, AppMotion.standard);
  });

  testWidgets('returns zero duration when animations are disabled', (
    tester,
  ) async {
    Duration? resolved;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            resolved = AppMotion.resolve(context, AppMotion.deliberate);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, Duration.zero);
  });
}
