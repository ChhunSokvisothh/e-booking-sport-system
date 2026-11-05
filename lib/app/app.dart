import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';
import '../shared/ui/app_theme.dart';

class EBookingApp extends StatelessWidget {
  const EBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Booking Sports',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
