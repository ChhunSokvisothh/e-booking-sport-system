import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design tokens for the app. Use these instead of hardcoded colors.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF0E5E4A); // pitch green
  static const Color primaryDark = Color(0xFF0A4A3A);
  static const Color accent = Color(0xFFC6F432); // electric lime
  static const Color onAccent = Color(0xFF0B1220);

  // Neutrals
  static const Color ink = Color(0xFF0B1220);
  static const Color inkSoft = Color(0xFF475569);
  static const Color muted = Color(0xFF94A3B8);
  static const Color background = Color(0xFFF5F7F2);
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFEEF2EA);
  static const Color border = Color(0xFFE3E8DF);

  // Status
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E5E4A), Color(0xFF0B1220)],
  );
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double pill = 999;
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.danger,
    outlineVariant: AppColors.border,
  );

  final body = GoogleFonts.manropeTextTheme();
  final display = GoogleFonts.soraTextTheme();
  final textTheme = body
      .copyWith(
        displayLarge: display.displayLarge,
        displayMedium: display.displayMedium,
        displaySmall: display.displaySmall,
        headlineLarge: display.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      )
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  final roundedMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: const IconThemeData(color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: roundedMd,
      iconColor: AppColors.primary,
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: roundedMd,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: AppColors.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
      labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
      prefixIconColor: AppColors.inkSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      secondarySelectedColor: AppColors.ink,
      checkmarkColor: AppColors.accent,
      labelStyle: textTheme.labelLarge?.copyWith(color: AppColors.ink),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: const BorderSide(color: AppColors.border),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 68,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? AppColors.onAccent : AppColors.inkSoft);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.ink : AppColors.inkSoft,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceAlt,
        minimumSize: const Size(0, 52),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: roundedMd,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        minimumSize: const Size(0, 52),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        shape: roundedMd,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 52),
        textStyle: textTheme.labelLarge,
        tapTargetSize: MaterialTapTargetSize.padded,
        side: const BorderSide(color: AppColors.border, width: 1.2),
        shape: roundedMd,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: textTheme.labelLarge,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.ink,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
