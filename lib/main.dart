
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';\nimport 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'features/auth/data/auth_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final initialSession = await loadStoredAuthSession();

  runApp(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((_) => initialSession),
      ],
      child: const EBookingApp(),
    ),
  );
}
