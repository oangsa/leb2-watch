import 'package:flutter/material.dart';

abstract final class AppColors {
  static const cobalt = Color(0xFF2854C7);
  static const transparent = Color(0x00000000);

  static const lightPrimary = cobalt;
  static const lightOnPrimary = Color(0xFFFDFDFF);
  static const lightPrimaryContainer = Color(0xFFDDE6FF);
  static const lightOnPrimaryContainer = Color(0xFF16316F);
  static const lightSurface = Color(0xFFF7F8FC);
  static const lightSurfaceBright = Color(0xFFFDFDFF);
  static const lightSurfaceDim = Color(0xFFE0E4EC);
  static const lightSurfaceContainerLowest = Color(0xFFFDFDFF);
  static const lightSurfaceContainerLow = Color(0xFFF2F4F8);
  static const lightSurfaceContainer = Color(0xFFECEFF5);
  static const lightSurfaceContainerHigh = Color(0xFFE5E9F1);
  static const lightSurfaceContainerHighest = Color(0xFFDDE2EC);
  static const lightOnSurface = Color(0xFF171A22);
  static const lightOnSurfaceVariant = Color(0xFF475066);
  static const lightOutline = Color(0xFF70798B);
  static const lightOutlineVariant = Color(0xFFC8CEDA);
  static const lightError = Color(0xFFB42318);
  static const lightOnError = Color(0xFFFDFDFF);
  static const lightErrorContainer = Color(0xFFFDE5E2);
  static const lightOnErrorContainer = Color(0xFF7A271A);

  static const darkPrimary = Color(0xFFAFC6FF);
  static const darkOnPrimary = Color(0xFF102B66);
  static const darkPrimaryContainer = Color(0xFF29467F);
  static const darkOnPrimaryContainer = Color(0xFFDCE5FF);
  static const darkSurface = Color(0xFF111319);
  static const darkSurfaceBright = Color(0xFF373A43);
  static const darkSurfaceDim = darkSurface;
  static const darkSurfaceContainerLowest = Color(0xFF0C0E13);
  static const darkSurfaceContainerLow = Color(0xFF181B22);
  static const darkSurfaceContainer = Color(0xFF1E2129);
  static const darkSurfaceContainerHigh = Color(0xFF272B34);
  static const darkSurfaceContainerHighest = Color(0xFF303540);
  static const darkOnSurface = Color(0xFFE7E9F0);
  static const darkOnSurfaceVariant = Color(0xFFB9C0CE);
  static const darkOutline = Color(0xFF8B94A4);
  static const darkOutlineVariant = Color(0xFF3B414C);
  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkErrorContainer = Color(0xFF4C211F);
  static const darkOnErrorContainer = Color(0xFFFFC7C2);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppRadii {
  static const control = 6.0;
  static const panel = 8.0;
  static const prominent = 12.0;
}

abstract final class AppBorders {
  static const hairline = 1.0;
}

abstract final class AppElevation {
  static const flat = 0.0;
  static const raised = 1.0;
  static const overlay = 3.0;
}

abstract final class AppSizing {
  static const minimumInteractive = 48.0;
  static const stateContentMaxWidth = 440.0;
  static const stateIcon = 32.0;
}

abstract final class AppTypography {
  static const displayLargeSize = 48.0;
  static const displayLargeHeight = 56 / 48;
  static const displayMediumSize = 40.0;
  static const displayMediumHeight = 48 / 40;
  static const displaySmallSize = 34.0;
  static const displaySmallHeight = 42 / 34;

  static const headlineLargeSize = 30.0;
  static const headlineLargeHeight = 38 / 30;
  static const headlineMediumSize = 26.0;
  static const headlineMediumHeight = 34 / 26;
  static const headlineSmallSize = 22.0;
  static const headlineSmallHeight = 30 / 22;

  static const titleLargeSize = 20.0;
  static const titleLargeHeight = 28 / 20;
  static const titleMediumSize = 16.0;
  static const titleMediumHeight = 24 / 16;
  static const titleSmallSize = 14.0;
  static const titleSmallHeight = 20 / 14;

  static const bodyLargeSize = 16.0;
  static const bodyLargeHeight = 24 / 16;
  static const bodyMediumSize = 14.0;
  static const bodyMediumHeight = 20 / 14;
  static const bodySmallSize = 12.0;
  static const bodySmallHeight = 18 / 12;

  static const labelLargeSize = 14.0;
  static const labelLargeHeight = 20 / 14;
  static const labelMediumSize = 12.0;
  static const labelMediumHeight = 16 / 12;
  static const labelSmallSize = 11.0;
  static const labelSmallHeight = 16 / 11;

  static const headingWeight = FontWeight.w600;
  static const bodyWeight = FontWeight.w400;
  static const labelWeight = FontWeight.w600;
}
