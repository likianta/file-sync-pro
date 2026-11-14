/// Minimal HTTP client shared by the remote file store and manifest scanner.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

final class RemoteException implements Exception {
  RemoteException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'RemoteException($statusCode): $message';
}

final class HttpTransport {
  HttpTransport({
    required String baseUrl,
    this.token = '',
    this.timeout = const Duration(minutes: 5),
    HttpClient? client,
  }) : baseUri = Uri.parse(_normalizeBaseUrl(baseUrl)),
       _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.userAgent = '$appName/$protocolVersion';
  }

  final Uri baseUri;
  final String token;
  final Duration timeout;
  final HttpClient _client;

  String get baseUrl => baseUri.toString();

  Uri endpoint(String operation, {Map<String, String>? query}) {
    return baseUri.resolve(operation).replace(queryParameters: query);
  }

  Future<Map<String, Object?>> getJson(
    String operation, {
    Map<String, String>? query,
  }) {
    return _retry(() async {
      final request = await _open('GET', operation, query: query);
      final response = await request.close().timeout(timeout);
      final text = await _readText(response);
      if (response.statusCode >= 400) {
        throw RemoteException(response.statusCode, _errorMessage(text));
      }
      return _asJsonMap(text);
    });
  }

  Future<void> post(String operation, {Map<String, String>? query}) {
    return _retry(() async {
      final request = await _open('POST', operation, query: query);
      request.contentLength = 0;
      final response = await request.close().timeout(timeout);
      final text = await _readText(response);
      if (response.statusCode >= 400) {
        throw RemoteException(response.statusCode, _errorMessage(text));
      }
    });
  }

  /// Returns the status code for non-server errors so callers can treat
  /// "not found" or "directory not empty" as ordinary outcomes.
  Future<int> delete(String operation, {Map<String, String>? query}) {
    return _retry(() async {
      final request = await _open('DELETE', operation, query: query);
      final response = await request.close().timeout(timeout);
      final text = await _readText(response);
      if (response.statusCode >= 500) {
        throw RemoteException(response.statusCode, _errorMessage(text));
      }
      return response.statusCode;
    });
  }

  Future<Map<String, Object?>> putStream(
    String operation,
    Stream<List<int>> data, {
    Map<String, String>? query,
  }) async {
    final request = await _open('PUT', operation, query: query);
    request.headers.contentType = ContentType.binary;
    await request.addStream(data);
    final response = await request.close().timeout(timeout);
    final text = await _readText(response);
    if (response.statusCode >= 400) {
      throw RemoteException(response.statusCode, _errorMessage(text));
    }
    return _asJsonMap(text);
  }

  Future<HttpClientResponse> getStream(
    String operation, {
    Map<String, String>? query,
  }) async {
    final request = await _open('GET', operation, query: query);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200 && response.statusCode != 206) {
      final text = await _readText(response);
      throw RemoteException(response.statusCode, _errorMessage(text));
    }
    return response;
  }

  Future<void> close() async {
    _client.close(force: true);
  }

  Future<T> _retry<T>(Future<T> Function() action) async {
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        return await action();
      } catch (error) {
        if (attempt >= maxAttempts || !_isRetryable(error)) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  static bool _isRetryable(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }
    if (error is RemoteException) {
      return error.statusCode >= 500 ||
          error.statusCode == 408 ||
          error.statusCode == 429;
    }
    return false;
  }

  Future<HttpClientRequest> _open(
    String method,
    String operation, {
    Map<String, String>? query,
  }) async {
    final request = await _client
        .openUrl(method, endpoint(operation, query: query))
        .timeout(const Duration(seconds: 30));
    if (token.isNotEmpty) {
      request.headers.set(tokenHeader, token);
    }
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    return request;
  }

  Future<String> _readText(HttpClientResponse response) {
    return utf8.decoder.bind(response).join().timeout(timeout);
  }

  static Map<String, Object?> _asJsonMap(String text) {
    if (text.isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, Object?>();
    throw const FormatException('Expected a JSON object');
  }

  static String _errorMessage(String text) {
    if (text.isEmpty) return 'Unknown server error';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // Fall through to raw text.
    }
    return text;
  }

  static String _normalizeBaseUrl(String baseUrl) {
    return baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  }
}
