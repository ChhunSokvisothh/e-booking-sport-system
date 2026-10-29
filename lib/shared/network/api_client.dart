import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _requestTimeout = Duration(seconds: 15);

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${AppConfig.backendBaseUrl}$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({String? token, bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Token $token',
    };
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
    String method,
    String path,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } on http.ClientException catch (e) {
      if (kDebugMode) {
        debugPrint('API network error $method $path: ${e.message}');
      }
      throw Exception('Network error. Please check your connection and try again.');
    }
  }

  Never _throwApiError(http.Response response, String method, String path) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    String message = response.body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message = (decoded['error'] ?? decoded['detail'] ?? response.body).toString();
      }
    } catch (_) {
      // Keep raw response body if server did not return JSON.
      if (contentType.contains('text/html')) {
        message = 'Server returned an HTML error page. Please verify backend logs.';
      }
    }

    if (message.length > 280) {
      message = '${message.substring(0, 280)}...';
    }

    if (kDebugMode) {
      debugPrint('API error $method $path (${response.statusCode}): $message');
    }

    if (response.statusCode == 401) {
      throw Exception('Your session has expired. Please sign in again.');
    }
    if (response.statusCode == 403) {
      throw Exception('You do not have permission for this action.');
    }
    if (response.statusCode == 404) {
      throw Exception('Requested resource was not found.');
    }
    if (response.statusCode >= 500) {
      throw Exception('Server is temporarily unavailable. Please try again shortly.');
    }
    if (response.statusCode == 400 && message.isNotEmpty) {
      throw Exception(message);
    }
    throw Exception(message.isEmpty ? 'Request failed. Please try again.' : message);
  }

  dynamic _decodeBody(http.Response response, String method, String path) {
    if (response.statusCode >= 400) {
      _throwApiError(response, method, path);
    }
    if (response.body.isEmpty) {
      return null;
    }
    return jsonDecode(response.body);
  }

  Future<List<dynamic>> getList(String path, [Map<String, String>? query, String? token]) async {
    final response = await _send(
      () => _client.get(_uri(path, query), headers: _headers(token: token, json: false)),
      'GET',
      path,
    );
    final decoded = _decodeBody(response, 'GET', path);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      final results = decoded['results'];
      if (results is List<dynamic>) {
        return results;
      }
    }
    throw Exception('Unexpected server response. Please try again.');
  }

  Future<Map<String, dynamic>> getPage(
    String path, {
    Map<String, String>? query,
    String? token,
  }) async {
    final response = await _send(
      () => _client.get(_uri(path, query), headers: _headers(token: token, json: false)),
      'GET',
      path,
    );
    final decoded = _decodeBody(response, 'GET', path);
    if (decoded is Map<String, dynamic> && decoded['results'] is List<dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected paginated server response. Please try again.');
  }

  Future<Map<String, dynamic>> getMap(String path, {Map<String, String>? query, String? token}) async {
    final response = await _send(
      () => _client.get(_uri(path, query), headers: _headers(token: token, json: false)),
      'GET',
      path,
    );
    final decoded = _decodeBody(response, 'GET', path);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected server response. Please try again.');
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {String? token}) async {
    final response = await _send(
      () => _client.post(
        _uri(path),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
      'POST',
      path,
    );

    final decoded = _decodeBody(response, 'POST', path);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected server response. Please try again.');
  }

  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body, {String? token}) async {
    final response = await _send(
      () => _client.patch(
        _uri(path),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
      'PATCH',
      path,
    );

    final decoded = _decodeBody(response, 'PATCH', path);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected server response. Please try again.');
  }

  Future<Map<String, dynamic>> deleteJson(String path, {String? token}) async {
    final response = await _send(
      () => _client.delete(
        _uri(path),
        headers: _headers(token: token),
      ),
      'DELETE',
      path,
    );

    final decoded = _decodeBody(response, 'DELETE', path);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected server response. Please try again.');
  }
}
