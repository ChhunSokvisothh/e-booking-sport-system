import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/auth_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
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
