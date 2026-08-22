import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'brand.dart';

/// Builds light & dark themes from a [BrandIdentity], using flex_color_scheme
/// for sane Material 3 defaults.
///
/// Display/headers: Playfair Display (classic, editorial — fits old-school
///                  barbers).
/// Body & UI text:  Inter (clean, neutral, highly readable on small screens).
///
/// Both are bundled in `assets/fonts` and referenced by family name. They used
/// to come from the `google_fonts` package, which downloads them from Google at
/// runtime — on the web build that means every customer who scans the QR code
/// hands their IP address to Google before they have booked anything. Bundling
/// is the whole fix: there is no network call left to switch off.
/// Family names as declared in `pubspec.yaml`. A typo here is silent — Flutter
/// falls back to the platform font rather than complaining — so they are named
/// once and referenced everywhere.
const String displayFamily = 'Playfair Display';
const String bodyFamily = 'Inter';

class AppTheme {
  /// [brand] paints light mode, [dark] paints dark mode. [dark] defaults to
  /// [brandDark], which is derived from the same shop configuration — passing
  /// it explicitly is for tests and for previewing a palette.
  AppTheme(this.brand, {BrandIdentity? dark}) : darkBrand = dark ?? brandDark;

  final BrandIdentity brand;
  final BrandIdentity darkBrand;

  TextTheme _buildTextTheme(ColorScheme cs) {
    final display = TextStyle(
      fontFamily: displayFamily,
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    );
    final body = TextStyle(fontFamily: bodyFamily, color: cs.onSurface);

    return TextTheme(
      displayLarge: display.copyWith(fontSize: 48, height: 1.05),
      displayMedium: display.copyWith(fontSize: 36, height: 1.10),
      displaySmall: display.copyWith(fontSize: 28, height: 1.15),
      headlineLarge: display.copyWith(fontSize: 26, height: 1.2),
      headlineMedium: display.copyWith(fontSize: 22, height: 1.25),
      headlineSmall: display.copyWith(
          fontSize: 18, height: 1.3, fontWeight: FontWeight.w500),
      titleLarge: body.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: body.copyWith(fontSize: 14, height: 1.45),
      bodySmall:
          body.copyWith(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
      labelLarge: body.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      labelMedium: body.copyWith(
          fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.4),
      labelSmall: body.copyWith(
          fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    );
  }

  ThemeData get light {
    final theme = FlexThemeData.light(
      colors: FlexSchemeColor(
        primary: brand.primary,
        primaryContainer: brand.primary.withValues(alpha: 0.10),
        secondary: brand.secondary,
        secondaryContainer: brand.secondary.withValues(alpha: 0.18),
        tertiary: brand.onSurface,
        tertiaryContainer: brand.background,
      ),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 8,
      scaffoldBackground: brand.background,
      appBarStyle: FlexAppBarStyle.background,
      appBarElevation: 0,
      tabBarStyle: FlexTabBarStyle.forBackground,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        useMaterial3Typography: true,
        defaultRadius: 14,
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 14,
        elevatedButtonRadius: 14,
        filledButtonRadius: 14,
        outlinedButtonRadius: 14,
        cardRadius: 18,
        chipRadius: 12,
        bottomSheetRadius: 24,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      swapLegacyOnMaterial3: true,
    );
    return theme.copyWith(textTheme: _buildTextTheme(theme.colorScheme));
  }

  ThemeData get dark {
    final b = darkBrand;
    final theme = FlexThemeData.dark(
      colors: FlexSchemeColor(
        primary: b.primary,
        primaryContainer: Color.lerp(b.primary, Colors.black, 0.45)!,
        secondary: b.secondary,
        secondaryContainer: b.secondary.withValues(alpha: 0.30),
        tertiary: b.onSurface,
        tertiaryContainer: b.surface,
      ),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 14,
      scaffoldBackground: b.background,
      appBarStyle: FlexAppBarStyle.background,
      appBarElevation: 0,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 16,
        useMaterial3Typography: true,
        defaultRadius: 14,
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 14,
        elevatedButtonRadius: 14,
        cardRadius: 18,
        chipRadius: 12,
        bottomSheetRadius: 24,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      swapLegacyOnMaterial3: true,
    );
    return theme.copyWith(textTheme: _buildTextTheme(theme.colorScheme));
  }
}
