// Hallmark · foundation: native Flutter design system
// Genre/theme: modern-minimal / Cobalt · scope: tokens, themes, feedback states
// Pre-emit critique: P5 H4 E5 S5 R5 V3

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_status_colors.dart';
import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light =>
      _build(brightness: Brightness.light, statusColors: AppStatusColors.light);

  static ThemeData get dark =>
      _build(brightness: Brightness.dark, statusColors: AppStatusColors.dark);

  static ThemeData _build({
    required Brightness brightness,
    required AppStatusColors statusColors,
  }) {
    final isLight = brightness == Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.cobalt,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: isLight ? AppColors.lightPrimary : AppColors.darkPrimary,
          onPrimary: isLight
              ? AppColors.lightOnPrimary
              : AppColors.darkOnPrimary,
          primaryContainer: isLight
              ? AppColors.lightPrimaryContainer
              : AppColors.darkPrimaryContainer,
          onPrimaryContainer: isLight
              ? AppColors.lightOnPrimaryContainer
              : AppColors.darkOnPrimaryContainer,
          surface: isLight ? AppColors.lightSurface : AppColors.darkSurface,
          surfaceBright: isLight
              ? AppColors.lightSurfaceBright
              : AppColors.darkSurfaceBright,
          surfaceDim: isLight
              ? AppColors.lightSurfaceDim
              : AppColors.darkSurfaceDim,
          surfaceContainerLowest: isLight
              ? AppColors.lightSurfaceContainerLowest
              : AppColors.darkSurfaceContainerLowest,
          surfaceContainerLow: isLight
              ? AppColors.lightSurfaceContainerLow
              : AppColors.darkSurfaceContainerLow,
          surfaceContainer: isLight
              ? AppColors.lightSurfaceContainer
              : AppColors.darkSurfaceContainer,
          surfaceContainerHigh: isLight
              ? AppColors.lightSurfaceContainerHigh
              : AppColors.darkSurfaceContainerHigh,
          surfaceContainerHighest: isLight
              ? AppColors.lightSurfaceContainerHighest
              : AppColors.darkSurfaceContainerHighest,
          onSurface: isLight
              ? AppColors.lightOnSurface
              : AppColors.darkOnSurface,
          onSurfaceVariant: isLight
              ? AppColors.lightOnSurfaceVariant
              : AppColors.darkOnSurfaceVariant,
          outline: isLight ? AppColors.lightOutline : AppColors.darkOutline,
          outlineVariant: isLight
              ? AppColors.lightOutlineVariant
              : AppColors.darkOutlineVariant,
          error: isLight ? AppColors.lightError : AppColors.darkError,
          onError: isLight ? AppColors.lightOnError : AppColors.darkOnError,
          errorContainer: isLight
              ? AppColors.lightErrorContainer
              : AppColors.darkErrorContainer,
          onErrorContainer: isLight
              ? AppColors.lightOnErrorContainer
              : AppColors.darkOnErrorContainer,
        );
    final platform = defaultTargetPlatform;
    final typography = Typography.material2021(
      platform: platform,
      colorScheme: scheme,
    );
    final textTheme = _textTheme(isLight ? typography.black : typography.white);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    final controlMinimumSize = WidgetStatePropertyAll(
      Size.square(AppSizing.minimumInteractive),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      platform: platform,
      typography: typography,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      focusColor: scheme.primary,
      extensions: [statusColors],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLowest,
        foregroundColor: scheme.onSurface,
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.flat,
        surfaceTintColor: AppColors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: AppElevation.flat,
        surfaceTintColor: AppColors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: AppTypography.labelWeight,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(
          color: scheme.onPrimaryContainer,
          size: 24,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: AppTypography.labelWeight,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minVerticalPadding: AppSpacing.xs,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: AppColors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.prominent),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: controlMinimumSize,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: controlMinimumSize,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          shape: WidgetStatePropertyAll(controlShape),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outline, width: AppBorders.hairline),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: controlMinimumSize,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(minimumSize: controlMinimumSize),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.outline,
            width: AppBorders.hairline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.outline,
            width: AppBorders.hairline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.primary,
            width: AppBorders.hairline,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.error,
            width: AppBorders.hairline,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.error,
            width: AppBorders.hairline,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: AppBorders.hairline,
        space: AppBorders.hairline,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: AppTypography.displayLargeSize,
        height: AppTypography.displayLargeHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: AppTypography.displayMediumSize,
        height: AppTypography.displayMediumHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: AppTypography.displaySmallSize,
        height: AppTypography.displaySmallHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: AppTypography.headlineLargeSize,
        height: AppTypography.headlineLargeHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: AppTypography.headlineMediumSize,
        height: AppTypography.headlineMediumHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: AppTypography.headlineSmallSize,
        height: AppTypography.headlineSmallHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: AppTypography.titleLargeSize,
        height: AppTypography.titleLargeHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: AppTypography.titleMediumSize,
        height: AppTypography.titleMediumHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: AppTypography.titleSmallSize,
        height: AppTypography.titleSmallHeight,
        fontWeight: AppTypography.headingWeight,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: AppTypography.bodyLargeSize,
        height: AppTypography.bodyLargeHeight,
        fontWeight: AppTypography.bodyWeight,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: AppTypography.bodyMediumSize,
        height: AppTypography.bodyMediumHeight,
        fontWeight: AppTypography.bodyWeight,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: AppTypography.bodySmallSize,
        height: AppTypography.bodySmallHeight,
        fontWeight: AppTypography.bodyWeight,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: AppTypography.labelLargeSize,
        height: AppTypography.labelLargeHeight,
        fontWeight: AppTypography.labelWeight,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: AppTypography.labelMediumSize,
        height: AppTypography.labelMediumHeight,
        fontWeight: AppTypography.labelWeight,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: AppTypography.labelSmallSize,
        height: AppTypography.labelSmallHeight,
        fontWeight: AppTypography.labelWeight,
      ),
    );
  }
}
