import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_breakpoints.dart';

void main() {
  group('AppBreakpoints.classify', () {
    test('classifies exact compact, medium, and expanded edges', () {
      expect(AppBreakpoints.classify(0), AppWindowClass.compact);
      expect(AppBreakpoints.classify(599.9), AppWindowClass.compact);
      expect(AppBreakpoints.classify(600), AppWindowClass.medium);
      expect(AppBreakpoints.classify(1199.9), AppWindowClass.medium);
      expect(AppBreakpoints.classify(1200), AppWindowClass.expanded);
      expect(AppBreakpoints.classify(2400), AppWindowClass.expanded);
    });

    test('rejects negative and non-finite widths', () {
      expect(() => AppBreakpoints.classify(-1), throwsArgumentError);
      expect(() => AppBreakpoints.classify(double.nan), throwsArgumentError);
      expect(
        () => AppBreakpoints.classify(double.infinity),
        throwsArgumentError,
      );
      expect(
        () => AppBreakpoints.classify(double.negativeInfinity),
        throwsArgumentError,
      );
    });
  });

  testWidgets('reads the current window width from MediaQuery', (tester) async {
    AppWindowClass? windowClass;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Builder(
          builder: (context) {
            windowClass = AppBreakpoints.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(windowClass, AppWindowClass.medium);
  });
}
