import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../shared/config/app_config.dart';

class TelegramAuthService {
  static http.Client? _activeClient;
  static bool _cancelled = false;
  static Uri? _activeTelegramAppUri;
  static Uri? _activeTelegramWebUri;

  static const String _botUsername = String.fromEnvironment(
    'TELEGRAM_BOT_USERNAME',
    defaultValue: 'SportsSystemBot',
  );

  static void cancel() {
    _cancelled = true;
    _activeClient?.close();
    _activeClient = null;
    _activeTelegramAppUri = null;
    _activeTelegramWebUri = null;
  }

  static Future<bool> openTelegram() async {
    final appUri = _activeTelegramAppUri;
    if (appUri != null) {
      try {
        if (await launchUrl(appUri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Fall back to Telegram's HTTPS link if tg:// is unavailable.
      }
    }

    final webUri = _activeTelegramWebUri;
    if (webUri == null) return false;
    try {
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> login({void Function(String code)? onCodeCreated}) async {
    _cancelled = false;
    final client = http.Client();
    _activeClient = client;
    final configuredBaseUrl = AppConfig.backendBaseUrl;
    final baseUrl = configuredBaseUrl.endsWith('/')
        ? configuredBaseUrl.substring(0, configuredBaseUrl.length - 1)
        : configuredBaseUrl;
    try {
      final startResponse = await client
          .post(Uri.parse('$baseUrl/api/auth/telegram/start'))
          .timeout(const Duration(seconds: 15));
      _throwIfCancelled();
      if (startResponse.statusCode < 200 || startResponse.statusCode >= 300) {
        throw Exception(_serverMessage(startResponse, 'Could not start Telegram login'));
      }
      final startData = jsonDecode(startResponse.body) as Map<String, dynamic>;
      final code = startData['token'] as String?;
      if (code == null || code.isEmpty) {
        throw Exception('Telegram login code was missing.');
      }
      onCodeCreated?.call(code);

      final username = _botUsername.startsWith('@') ? _botUsername.substring(1) : _botUsername;
      _activeTelegramAppUri = Uri(
        scheme: 'tg',
        host: 'resolve',
        queryParameters: {'domain': username, 'start': code},
      );
      _activeTelegramWebUri = Uri.https('t.me', '/$username', {'start': code});
      if (!await openTelegram()) {
        throw Exception('Could not open Telegram.');
      }

      final stopwatch = Stopwatch()..start();
      const timeout = Duration(minutes: 4, seconds: 50);
      while (stopwatch.elapsed < timeout) {
        final response = await client
            .post(Uri.parse('$baseUrl/api/auth/telegram/status'), body: {'token': code})
            .timeout(timeout - stopwatch.elapsed);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_serverMessage(response, 'Could not check Telegram login status'));
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _throwIfCancelled();
        if (data['status'] == 'done') {
          return data;
        }
        if (data['status'] == 'expired') {
          throw Exception('This Telegram sign-in code expired. Start again and complete Telegram within five minutes.');
        }
        if (data['status'] == 'error' || data['status'] == 'failed') {
          throw Exception('The sign-in code was not found by the backend. Check the Telegram webhook, then try again.');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      throw TimeoutException('Telegram did not complete sign-in in time. Check the bot webhook URL and secret, then try again.');
    } catch (_) {
      if (_cancelled) {
        throw Exception('Telegram sign-in cancelled.');
      }
      rethrow;
    } finally {
      client.close();
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      _activeTelegramAppUri = null;
      _activeTelegramWebUri = null;
    }
  }

  static void _throwIfCancelled() {
    if (_cancelled) {
      throw Exception('Telegram sign-in cancelled.');
    }
  }

  static String _serverMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['error'] is String) {
        return body['error'] as String;
      }
    } on FormatException {
      // Proxies and server errors may return HTML instead of JSON.
    }
    return '$fallback (HTTP ${response.statusCode}).';
  }
}
