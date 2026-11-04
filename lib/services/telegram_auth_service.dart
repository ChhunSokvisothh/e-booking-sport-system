
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
        if (await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        )) {
          return true;
        }
      } catch (_) {
        // Fall back to Telegram HTTPS URL.
      }
    }

    final webUri = _activeTelegramWebUri;
    if (webUri == null) return false;

    try {
      return await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> login({
    void Function(String code)? onCodeCreated,
  }) async {
    _cancelled = false;

    final client = http.Client();
    _activeClient = client;

    final configuredBaseUrl = AppConfig.backendBaseUrl;
    final baseUrl = configuredBaseUrl.endsWith('/')
        ? configuredBaseUrl.substring(0, configuredBaseUrl.length - 1)
        : configuredBaseUrl;

    try {
      // --------------------------------------------------
      // 1. Start Telegram login
      // --------------------------------------------------

      final startResponse = await client
          .post(
            Uri.parse('$baseUrl/api/auth/telegram/start/'),
          )
          .timeout(const Duration(seconds: 15));

      _throwIfCancelled();

      if (startResponse.statusCode < 200 ||
          startResponse.statusCode >= 300) {
        throw Exception(
          _serverMessage(
            startResponse,
            'Could not start Telegram login',
          ),
        );
      }

      final startData =
          jsonDecode(startResponse.body) as Map<String, dynamic>;

      // Backend returns telegram_url
      final telegramUrl = startData['telegram_url'] as String?;

      if (telegramUrl == null || telegramUrl.isEmpty) {
        throw Exception('Telegram login URL was missing from the server.');
      }

      // Extract the temporary login code from ?start=...
      final telegramUri = Uri.parse(telegramUrl);
      final code = telegramUri.queryParameters['start'];

      if (code == null || code.isEmpty) {
        throw Exception('Telegram login code was missing from the URL.');
      }

      onCodeCreated?.call(code);

      // --------------------------------------------------
      // 2. Prepare Telegram app and browser URLs
      // --------------------------------------------------

      final username = _botUsername.startsWith('@')
          ? _botUsername.substring(1)
          : _botUsername;

      _activeTelegramAppUri = Uri(
        scheme: 'tg',
        host: 'resolve',
        queryParameters: {
          'domain': username,
          'start': code,
        },
      );

      // Use the exact URL returned by Django.
      _activeTelegramWebUri = telegramUri;

      if (!await openTelegram()) {
        throw Exception('Could not open Telegram.');
      }

      _throwIfCancelled();

      // --------------------------------------------------
      // 3. Poll backend for Telegram confirmation
      // --------------------------------------------------

      final stopwatch = Stopwatch()..start();

      const timeout = Duration(minutes: 4, seconds: 50);
      const pollingInterval = Duration(seconds: 2);

      while (stopwatch.elapsed < timeout) {
        _throwIfCancelled();

        final remaining = timeout - stopwatch.elapsed;

        final response = await client
            .post(
              Uri.parse('$baseUrl/api/auth/telegram/status/'),
              body: {
                // Backend expects "code", not "token".
                'code': code,
              },
            )
            .timeout(remaining);

        _throwIfCancelled();

        if (response.statusCode < 200 ||
            response.statusCode >= 300) {
          throw Exception(
            _serverMessage(
              response,
              'Could not check Telegram login status',
            ),
          );
        }

        final data =
            jsonDecode(response.body) as Map<String, dynamic>;

        final status = data['status'];

        // Django returns "authenticated" after successful exchange.
        if (status == 'authenticated') {
          return data;
        }

        if (status == 'expired') {
          throw Exception(
            'This Telegram sign-in code expired. '
            'Start again and complete Telegram within five minutes.',
          );
        }

        if (status == 'error' || status == 'failed') {
          throw Exception(
            'Telegram sign-in failed. Check the Telegram webhook '
            'and try again.',
          );
        }

        // "pending" means the user has not confirmed through Telegram.
        await Future<void>.delayed(pollingInterval);
      }

      throw TimeoutException(
        'Telegram did not complete sign-in in time. '
        'Check the bot webhook URL and try again.',
      );
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

  static String _serverMessage(
    http.Response response,
    String fallback,
  ) {
    try {
      final body = jsonDecode(response.body);

      if (body is Map<String, dynamic> &&
          body['error'] is String) {
        return body['error'] as String;
      }
    } on FormatException {
      // Server may return HTML instead of JSON.
    }

    return '$fallback (HTTP ${response.statusCode}).';
  }
}
