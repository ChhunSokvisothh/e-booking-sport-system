import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _backendUrlFromEnv = String.fromEnvironment('BACKEND_URL', defaultValue: '');

  static String get backendBaseUrl {
    final configured = _backendUrlFromEnv.trim();
    if (configured.isNotEmpty) {
      return configured.endsWith('/') ? configured.substring(0, configured.length - 1) : configured;
    }

    if (kIsWeb) {
      return 'http://localhost:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:8000';
    }
  }
}
