import 'package:flutter/widgets.dart';

enum AppWindowClass { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const medium = 600.0;
  static const expanded = 1200.0;

  static AppWindowClass classify(double width) {
    if (!width.isFinite || width < 0) {
      throw ArgumentError.value(
        width,
        'width',
        'Width must be finite and non-negative.',
      );
    }
    if (width < medium) {
      return AppWindowClass.compact;
    }
    if (width < expanded) {
      return AppWindowClass.medium;
    }
    return AppWindowClass.expanded;
  }

  static AppWindowClass of(BuildContext context) {
    return classify(MediaQuery.sizeOf(context).width);
  }
}
