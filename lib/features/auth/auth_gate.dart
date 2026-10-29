import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auth_session.dart';
import 'auth_screen.dart';
import '../booking/home_shell.dart';
import '../owner/owner_home_shell.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return const AuthScreen();
    }
    switch (session.role) {
      case 'owner':
        return const OwnerHomeShell();
      case 'user':
      default:
        return const HomeShell();
    }
  }
}
