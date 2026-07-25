import 'package:flutter/material.dart';

@immutable
final class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.staleContainer,
    required this.onStaleContainer,
    required this.informationContainer,
    required this.onInformationContainer,
  });

  static const light = AppStatusColors(
    successContainer: Color(0xFFDDF6E8),
    onSuccessContainer: Color(0xFF14532D),
    warningContainer: Color(0xFFFFF0C2),
    onWarningContainer: Color(0xFF713F12),
    errorContainer: Color(0xFFFDE5E2),
    onErrorContainer: Color(0xFF7A271A),
    staleContainer: Color(0xFFE8EBF0),
    onStaleContainer: Color(0xFF3F4652),
    informationContainer: Color(0xFFE1E9FF),
    onInformationContainer: Color(0xFF183B8F),
  );

  static const dark = AppStatusColors(
    successContainer: Color(0xFF183D2A),
    onSuccessContainer: Color(0xFFB9F6D0),
    warningContainer: Color(0xFF49340D),
    onWarningContainer: Color(0xFFFFE099),
    errorContainer: Color(0xFF4C211F),
    onErrorContainer: Color(0xFFFFC7C2),
    staleContainer: Color(0xFF30343D),
    onStaleContainer: Color(0xFFDCE1EA),
    informationContainer: Color(0xFF1D315F),
    onInformationContainer: Color(0xFFC8D6FF),
  );

  final Color successContainer;
  final Color onSuccessContainer;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color staleContainer;
  final Color onStaleContainer;
  final Color informationContainer;
  final Color onInformationContainer;

  static AppStatusColors of(BuildContext context) {
    final colors = Theme.of(context).extension<AppStatusColors>();
    if (colors == null) {
      throw FlutterError(
        'AppStatusColors is missing from the active ThemeData extensions.',
      );
    }
    return colors;
  }

  @override
  AppStatusColors copyWith({
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? staleContainer,
    Color? onStaleContainer,
    Color? informationContainer,
    Color? onInformationContainer,
  }) {
    return AppStatusColors(
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      staleContainer: staleContainer ?? this.staleContainer,
      onStaleContainer: onStaleContainer ?? this.onStaleContainer,
      informationContainer: informationContainer ?? this.informationContainer,
      onInformationContainer:
          onInformationContainer ?? this.onInformationContainer,
    );
  }

  @override
  AppStatusColors lerp(covariant AppStatusColors? other, double t) {
    if (other == null) {
      return this;
    }
    return AppStatusColors(
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(
        onErrorContainer,
        other.onErrorContainer,
        t,
      )!,
      staleContainer: Color.lerp(staleContainer, other.staleContainer, t)!,
      onStaleContainer: Color.lerp(
        onStaleContainer,
        other.onStaleContainer,
        t,
      )!,
      informationContainer: Color.lerp(
        informationContainer,
        other.informationContainer,
        t,
      )!,
      onInformationContainer: Color.lerp(
        onInformationContainer,
        other.onInformationContainer,
        t,
      )!,
    );
  }
}
