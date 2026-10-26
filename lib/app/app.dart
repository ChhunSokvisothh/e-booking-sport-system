import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/auth/auth_gate.dart';

class EBookingApp extends StatelessWidget {
  const EBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme() as TextTheme;

    return MaterialApp(
      title: 'E-Booking Sports',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: baseTextTheme,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFF1F5F9),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111318),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF111318)),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          showDragHandle: true,
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titleTextStyle: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111318),
          ),
          contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
            color: const Color(0xFF4B5563),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: Colors.white),
          actionTextColor: const Color(0xFF99F6E4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          labelStyle: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          selectedColor: colorScheme.primary.withValues(alpha: 0.14),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 0,
          backgroundColor: Colors.white,
          indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = media.textScaler.scale(1.0).clamp(0.9, 1.5);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
    );
  }
}
