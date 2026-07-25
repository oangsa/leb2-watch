import 'package:flutter/widgets.dart';

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const deliberate = Duration(milliseconds: 240);

  static bool reduce(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  static Duration resolve(BuildContext context, Duration duration) {
    return reduce(context) ? Duration.zero : duration;
  }
}
