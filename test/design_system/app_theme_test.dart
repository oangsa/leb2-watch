import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_status_colors.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/app/design_system/app_tokens.dart';

void main() {
  group('AppTheme', () {
    test('builds explicit Material 3 light and dark themes', () {
      final light = AppTheme.light;
      final dark = AppTheme.dark;

      expect(light.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(light.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(light.colorScheme.primary, AppColors.lightPrimary);
      expect(light.colorScheme.surface, AppColors.lightSurface);
      expect(light.extension<AppStatusColors>(), AppStatusColors.light);

      expect(dark.useMaterial3, isTrue);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(dark.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(dark.colorScheme.primary, AppColors.darkPrimary);
      expect(dark.colorScheme.surface, AppColors.darkSurface);
      expect(dark.extension<AppStatusColors>(), AppStatusColors.dark);
    });

    test('keeps core and semantic text contrast at or above 4.5:1', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final scheme = theme.colorScheme;
        final status = theme.extension<AppStatusColors>()!;
        final pairs = <(String, Color, Color)>[
          ('primary', scheme.onPrimary, scheme.primary),
          (
            'primary container',
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          ),
          ('surface', scheme.onSurface, scheme.surface),
          (
            'surface container',
            scheme.onSurfaceVariant,
            scheme.surfaceContainer,
          ),
          ('error', scheme.onError, scheme.error),
          ('error container', scheme.onErrorContainer, scheme.errorContainer),
          (
            'success container',
            status.onSuccessContainer,
            status.successContainer,
          ),
          (
            'warning container',
            status.onWarningContainer,
            status.warningContainer,
          ),
          (
            'status error container',
            status.onErrorContainer,
            status.errorContainer,
          ),
          ('stale container', status.onStaleContainer, status.staleContainer),
          (
            'information container',
            status.onInformationContainer,
            status.informationContainer,
          ),
        ];

        for (final (name, foreground, background) in pairs) {
          expect(
            _contrastRatio(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.brightness} $name must meet WCAG AA.',
          );
        }
      }
    });

    test('keeps meaningful boundaries at or above 3:1', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final scheme = theme.colorScheme;

        expect(
          _contrastRatio(scheme.outline, scheme.surface),
          greaterThanOrEqualTo(3),
          reason: '${theme.brightness} outline boundary must remain visible.',
        );
        expect(
          _contrastRatio(theme.focusColor, scheme.surface),
          greaterThanOrEqualTo(3),
          reason: '${theme.brightness} focus signal must remain visible.',
        );
      }
    });

    test('defines typography hierarchy and component minima', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(
          theme.textTheme.displayLarge?.fontSize,
          AppTypography.displayLargeSize,
        );
        expect(
          theme.textTheme.displayLarge?.height,
          closeTo(AppTypography.displayLargeHeight, 0.0001),
        );
        expect(
          theme.textTheme.displayLarge?.fontWeight,
          AppTypography.headingWeight,
        );
        expect(
          theme.textTheme.bodyLarge?.fontSize,
          AppTypography.bodyLargeSize,
        );
        expect(
          theme.textTheme.bodyLarge?.height,
          closeTo(AppTypography.bodyLargeHeight, 0.0001),
        );
        expect(theme.textTheme.bodyLarge?.fontWeight, AppTypography.bodyWeight);
        expect(
          theme.textTheme.labelLarge?.fontWeight,
          AppTypography.labelWeight,
        );

        final filledMinimum = theme.filledButtonTheme.style?.minimumSize
            ?.resolve(const <WidgetState>{});
        final outlinedMinimum = theme.outlinedButtonTheme.style?.minimumSize
            ?.resolve(const <WidgetState>{});
        final textMinimum = theme.textButtonTheme.style?.minimumSize?.resolve(
          const <WidgetState>{},
        );
        final iconMinimum = theme.iconButtonTheme.style?.minimumSize?.resolve(
          const <WidgetState>{},
        );

        for (final size in [
          filledMinimum,
          outlinedMinimum,
          textMinimum,
          iconMinimum,
        ]) {
          expect(size?.width, greaterThanOrEqualTo(48));
          expect(size?.height, greaterThanOrEqualTo(48));
        }
        expect(theme.cardTheme.elevation, AppElevation.flat);
        expect(theme.appBarTheme.elevation, AppElevation.flat);
        expect(theme.dividerTheme.thickness, AppBorders.hairline);
      }
    });

    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('preserves $platform Material typography metadata', () {
        final themes = _themesForPlatform(platform);
        final expected = Typography.material2021(platform: platform);

        _expectTypographyMetadata(
          actual: themes.light.textTheme,
          expected: expected.black,
          platform: platform,
          brightness: Brightness.light,
        );
        _expectTypographyMetadata(
          actual: themes.dark.textTheme,
          expected: expected.white,
          platform: platform,
          brightness: Brightness.dark,
        );
      });
    }

    test('keeps every input border at one-pixel geometry', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final input = theme.inputDecorationTheme;
        final normal = input.border! as OutlineInputBorder;
        final enabled = input.enabledBorder! as OutlineInputBorder;
        final focused = input.focusedBorder! as OutlineInputBorder;
        final error = input.errorBorder! as OutlineInputBorder;
        final focusedError = input.focusedErrorBorder! as OutlineInputBorder;
        final expectedRadius = BorderRadius.circular(AppRadii.control);

        for (final border in [normal, enabled, focused, error, focusedError]) {
          expect(border.borderSide.width, AppBorders.hairline);
          expect(border.borderRadius, expectedRadius);
        }
        expect(normal.borderSide.color, theme.colorScheme.outline);
        expect(enabled.borderSide.color, theme.colorScheme.outline);
        expect(focused.borderSide.color, theme.colorScheme.primary);
        expect(error.borderSide.color, theme.colorScheme.error);
        expect(focusedError.borderSide.color, theme.colorScheme.error);
      }
    });
  });

  group('AppStatusColors', () {
    test('copyWith changes only supplied values', () {
      const replacement = Color(0xFF123456);

      final copied = AppStatusColors.light.copyWith(
        successContainer: replacement,
      );

      expect(copied.successContainer, replacement);
      expect(
        copied.onSuccessContainer,
        AppStatusColors.light.onSuccessContainer,
      );
      expect(
        copied.informationContainer,
        AppStatusColors.light.informationContainer,
      );
    });

    test('lerp interpolates every semantic role', () {
      final midpoint = AppStatusColors.light.lerp(AppStatusColors.dark, 0.5);

      expect(
        midpoint.successContainer,
        Color.lerp(
          AppStatusColors.light.successContainer,
          AppStatusColors.dark.successContainer,
          0.5,
        ),
      );
      expect(
        midpoint.onInformationContainer,
        Color.lerp(
          AppStatusColors.light.onInformationContainer,
          AppStatusColors.dark.onInformationContainer,
          0.5,
        ),
      );
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = math.max(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  final darker = math.min(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}

({ThemeData light, ThemeData dark}) _themesForPlatform(
  TargetPlatform platform,
) {
  final previous = debugDefaultTargetPlatformOverride;
  try {
    debugDefaultTargetPlatformOverride = platform;
    return (light: AppTheme.light, dark: AppTheme.dark);
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

void _expectTypographyMetadata({
  required TextTheme actual,
  required TextTheme expected,
  required TargetPlatform platform,
  required Brightness brightness,
}) {
  for (final (role, actualStyle, expectedStyle) in [
    ('displayLarge', actual.displayLarge, expected.displayLarge),
    ('bodyLarge', actual.bodyLarge, expected.bodyLarge),
    ('labelLarge', actual.labelLarge, expected.labelLarge),
  ]) {
    expect(
      actualStyle?.fontFamily,
      expectedStyle?.fontFamily,
      reason: '$brightness $platform $role must use platform font metadata.',
    );
    expect(
      actualStyle?.fontFamilyFallback,
      expectedStyle?.fontFamilyFallback,
      reason: '$brightness $platform $role must preserve platform fallbacks.',
    );
  }
}
