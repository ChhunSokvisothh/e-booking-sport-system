import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.userUuid,
    required this.email,
    this.role = 'user',
  });

  final String token;
  final int userId;
  final String userUuid;
  final String email;
  final String role;

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'user_id': userId,
      'user_uuid': userUuid,
      'email': email,
      'role': role,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String,
      userId: json['user_id'] as int,
      userUuid: json['user_uuid'] as String,
      email: json['email'] as String,
      role: (json['role'] as String?) ?? 'user',
    );
  }
}

const _authSessionStorageKey = 'auth_session_v1';

final authSessionProvider = StateProvider<AuthSession?>((ref) => null);

Future<AuthSession?> loadStoredAuthSession() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_authSessionStorageKey);
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    await prefs.remove(_authSessionStorageKey);
    return null;
  }
}

Future<void> persistAuthSession(AuthSession session) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_authSessionStorageKey, jsonEncode(session.toJson()));
}

Future<void> clearStoredAuthSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_authSessionStorageKey);
}