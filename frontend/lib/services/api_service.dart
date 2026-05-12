import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Custom exception for authentication failures.
/// Screens catch this to trigger navigation to login.
class AuthException implements Exception {
  final String message;
  final String? code;
  AuthException([this.message = 'Session expired. Please log in again.', this.code]);
  @override
  String toString() => message;
}

/// Thrown for any non-2xx response so callers can surface structured errors.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final dynamic body;

  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.body,
  });

  @override
  String toString() => message;
}

class ApiService {
  // ── Storage keys ────────────────────────────────────────────────
  static const _kAccessToken = 'auth.accessToken';
  static const _kRefreshToken = 'auth.refreshToken';
  static const _kAccessExpiresAt = 'auth.accessExpiresAtEpoch';
  static const _kUsername = 'auth.username';
  static const _kRoles = 'auth.roles';
  // Legacy keys (kept for migration of existing installs)
  static const _kLegacyToken = 'token';
  static const _kLegacyUsername = 'username';
  static const _kLegacyRoles = 'roles';

  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _apiPortOverride = String.fromEnvironment(
    'API_PORT',
    defaultValue: '8080',
  );

  final String baseUrl = _resolveBaseUrl();

  static String _resolveBaseUrl() {
    if (_apiBaseUrlOverride.isNotEmpty) {
      return _normalizeBaseUrl(_apiBaseUrlOverride);
    }

    if (kIsWeb) {
      final currentUri = Uri.base;
      final backendHost = currentUri.host.isEmpty
          ? 'localhost'
          : currentUri.host;
      final backendScheme = currentUri.scheme == 'https' ? 'https' : 'http';
      final backendPort = int.tryParse(_apiPortOverride) ?? 8080;

      return Uri(
        scheme: backendScheme,
        host: backendHost,
        port: backendPort,
        path: 'api',
      ).toString();
    }

    return 'http://localhost:8080/api';
  }

  static String _normalizeBaseUrl(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  /// Global navigator key – set from main.dart so ApiService can
  /// redirect to /login on auth failures from anywhere in the app.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // ── Refresh coordination ────────────────────────────────────────
  /// Ensures at most one /refresh request is in-flight; queued callers await.
  static Future<String?>? _refreshFuture;

  // ── Auth token helpers ──────────────────────────────────────────

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final modern = prefs.getString(_kAccessToken);
    if (modern != null && modern.isNotEmpty) return modern;
    // Legacy fallback.
    return prefs.getString(_kLegacyToken);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRefreshToken);
  }

  /// Returns the token, otherwise throws AuthException + redirects to login.
  Future<String> _requireToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      await _forceLogout();
      throw AuthException();
    }
    return token;
  }

  /// Persists tokens returned by /signin or /refresh.
  ///
  /// Accepts the JwtResponse shape:
  ///   { accessToken, refreshToken, expiresIn, refreshExpiresIn, issuedAt,
  ///     id, username, roles }
  Future<void> _saveSession(Map<String, dynamic> response) async {
    final prefs = await SharedPreferences.getInstance();
    final access = (response['accessToken'] ?? response['token']) as String?;
    if (access == null || access.isEmpty) return;

    await prefs.setString(_kAccessToken, access);
    await prefs.setString(_kLegacyToken, access); // back-compat for older code

    final refresh = response['refreshToken'] as String?;
    if (refresh != null && refresh.isNotEmpty) {
      await prefs.setString(_kRefreshToken, refresh);
    }

    final username = response['username'] as String?;
    if (username != null) {
      await prefs.setString(_kUsername, username);
      await prefs.setString(_kLegacyUsername, username);
    }

    final roles = (response['roles'] as List?)?.map((e) => e.toString()).toList();
    if (roles != null) {
      await prefs.setStringList(_kRoles, roles);
      await prefs.setStringList(_kLegacyRoles, roles);
    }

    final expiresIn = response['expiresIn'];
    if (expiresIn is int) {
      final expiresAt = DateTime.now()
          .add(Duration(seconds: expiresIn))
          .millisecondsSinceEpoch;
      await prefs.setInt(_kAccessExpiresAt, expiresAt);
    }
  }

  /// Backwards-compatible wrapper used by older callers that just pass
  /// the access token + username + roles.
  Future<void> saveToken(
    String token,
    String username,
    List<String> roles,
  ) async {
    await _saveSession({
      'accessToken': token,
      'username': username,
      'roles': roles,
    });
  }

  /// Saves the full /signin or /refresh response.
  Future<void> saveSession(Map<String, dynamic> response) =>
      _saveSession(response);

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUsername) ?? prefs.getString(_kLegacyUsername);
  }

  Future<List<String>> getRoles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kRoles) ??
        prefs.getStringList(_kLegacyRoles) ??
        const [];
  }

  /// Whether the cached access token will likely be valid for the next
  /// [leeway] seconds. Used to schedule proactive refreshes.
  Future<bool> isAccessTokenFresh({int leewaySeconds = 60}) async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_kAccessExpiresAt);
    if (expiresAt == null) return true; // assume fresh on first run
    final now = DateTime.now().millisecondsSinceEpoch;
    return expiresAt - now > leewaySeconds * 1000;
  }

  /// Tries to swap the refresh token for a new access token. Returns the new
  /// access token, or null if no refresh was possible. Coalesces concurrent
  /// callers behind a single in-flight request.
  Future<String?> _refreshAccessToken() {
    final inflight = _refreshFuture;
    if (inflight != null) return inflight;

    final future = _performRefresh().whenComplete(() {
      _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<String?> _performRefresh() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );
    } catch (_) {
      return null; // network error → fall through to logout
    }

    if (response.statusCode != 200) {
      return null;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(body);
    return body['accessToken'] as String?;
  }

  Future<void> logout() async {
    final refresh = await getRefreshToken();
    final prefs = await SharedPreferences.getInstance();

    // Tell the server to revoke the refresh token (best-effort).
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refresh}),
        );
      } catch (_) {/* offline logout is fine */}
    }

    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kAccessExpiresAt);
    await prefs.remove(_kUsername);
    await prefs.remove(_kRoles);
    await prefs.remove(_kLegacyToken);
    await prefs.remove(_kLegacyUsername);
    await prefs.remove(_kLegacyRoles);
  }

  /// Clears stored credentials and navigates to login screen.
  Future<void> _forceLogout() async {
    await logout();
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  // ── Centralized HTTP helpers (auth-aware, refresh-aware) ────────

  Map<String, String> _jsonAuth(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Map<String, String> _bearerOnly(String token) => {
    'Authorization': 'Bearer $token',
  };

  /// Detects a /refresh-eligible 401: server signals `code: token_expired`
  /// or surfaces it in the WWW-Authenticate header.
  bool _isTokenExpired(http.Response response) {
    if (response.statusCode != 401) return false;
    final www = response.headers['www-authenticate'];
    if (www != null && www.contains('token_expired')) return true;
    if (response.body.isEmpty) return false;
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['code'] == 'token_expired') return true;
    } catch (_) {/* not JSON */}
    return false;
  }

  /// Performs the request and, if the server says the access token is
  /// expired, runs a single silent refresh and retries once.
  Future<http.Response> _authedRequest(
    Future<http.Response> Function(String token) send,
  ) async {
    final token = await _requireToken();
    http.Response response = await send(token);

    if (_isTokenExpired(response)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed != null && refreshed.isNotEmpty) {
        response = await send(refreshed);
      }
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _forceLogout();
      throw AuthException(_extractErrorMessage(response));
    }
    return response;
  }

  Future<http.Response> _authGet(String path) {
    return _authedRequest((t) => http.get(
          Uri.parse('$baseUrl$path'),
          headers: _bearerOnly(t),
        ));
  }

  Future<http.Response> _authPost(String path, {Map<String, dynamic>? body}) {
    return _authedRequest((t) => http.post(
          Uri.parse('$baseUrl$path'),
          headers: _jsonAuth(t),
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  Future<http.Response> _authDelete(String path) {
    return _authedRequest((t) => http.delete(
          Uri.parse('$baseUrl$path'),
          headers: _bearerOnly(t),
        ));
  }

  String _extractErrorMessage(http.Response response, {String? fallback}) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final msg = body['message'] ?? body['error'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {/* non-JSON */}
    return fallback ?? 'Request failed (${response.statusCode})';
  }

  ApiException _toApiException(http.Response response, {String? fallback}) {
    String code = 'request_failed';
    dynamic body;
    try {
      body = jsonDecode(response.body);
      if (body is Map && body['code'] is String) {
        code = body['code'] as String;
      }
    } catch (_) {/* non-JSON */}
    return ApiException(
      status: response.statusCode,
      code: code,
      message: _extractErrorMessage(response, fallback: fallback),
      body: body,
    );
  }

  // ── Authentication (public, no token needed) ────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/signin'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (e) {
      throw ApiException(
        status: 0,
        code: 'network_error',
        message: 'Cannot connect to server. Is the backend running?',
      );
    }
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await _saveSession(body);
      return body;
    }
    throw _toApiException(response, fallback: 'Login failed');
  }

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (e) {
      throw ApiException(
        status: 0,
        code: 'network_error',
        message: 'Cannot connect to server. Is the backend running?',
      );
    }
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw _toApiException(response, fallback: 'Registration failed');
  }

  /// Validates the current session by hitting /auth/me. Returns the profile
  /// payload on success, or throws AuthException on failure.
  Future<Map<String, dynamic>> me() async {
    final response = await _authGet('/auth/me');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw AuthException(_extractErrorMessage(response));
  }

  // ── Comments ────────────────────────────────────────────────────

  Future<List<dynamic>> getComments() async {
    final response = await http.get(Uri.parse('$baseUrl/comments'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load comments');
  }

  Future<void> postComment(String content) async {
    final response = await _authPost('/comments', body: {'content': content});
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Failed to post comment');
    }
  }

  Future<List<dynamic>> getPendingComments() async {
    final response = await _authGet('/comments/pending');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response,
        fallback: 'Failed to load pending comments');
  }

  Future<void> moderateComment(int id, bool approved) async {
    final response = await _authPost(
      '/comments/$id/moderate?approved=$approved',
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Failed to moderate comment');
    }
  }

  // ── Admin ───────────────────────────────────────────────────────

  Future<List<dynamic>> getUsers() async {
    final response = await _authGet('/admin/users');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load users');
  }

  Future<void> updateUserRole(int userId, String role) async {
    final response = await _authPost('/admin/users/$userId/role?role=$role');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Failed to update role');
    }
  }

  Future<Map<String, dynamic>> getAiSettings() async {
    final response = await _authGet('/admin/ai-settings');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load AI settings');
  }

  Future<void> updateAiSettings(double threshold, String activeModel) async {
    final response = await _authPost(
      '/admin/ai-settings',
      body: {'threshold': threshold, 'activeModel': activeModel},
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Failed to update AI settings');
    }
  }

  Future<List<dynamic>> getAllCommentsAdmin() async {
    final response = await _authGet('/admin/comments');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load all comments');
  }

  // ── Vision Lab ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getVisionLabInfo() async {
    final response = await http.get(Uri.parse('$baseUrl/vision-lab'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load vision lab info');
  }

  Future<Map<String, dynamic>> analyzeVisionImage(
    Uint8List imageBytes,
    String filename,
    String? contentType,
  ) async {
    final resolvedContentType = _resolveImageContentType(filename, contentType);

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/vision-lab'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'filename': filename,
          'contentType': resolvedContentType,
          'imageBase64': base64Encode(imageBytes),
        }),
      );
    } catch (e) {
      throw ApiException(
        status: 0,
        code: 'network_error',
        message:
            'Could not connect to the vision lab. Check that the backend is running.',
      );
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    if (response.statusCode == 413) {
      throw ApiException(
        status: 413,
        code: 'payload_too_large',
        message: 'Image is too large. Maximum size is 10 MB.',
      );
    }

    throw _toApiException(response, fallback: 'Vision lab request failed');
  }

  String _resolveImageContentType(String filename, String? contentType) {
    if (contentType != null && contentType.isNotEmpty) {
      return contentType;
    }

    final lowerFilename = filename.toLowerCase();
    if (lowerFilename.endsWith('.png')) return 'image/png';
    if (lowerFilename.endsWith('.gif')) return 'image/gif';
    if (lowerFilename.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Test message sentiment analysis
  Future<Map<String, dynamic>> testSentiment(String message) async {
    final response = await _authPost(
      '/comments/test-analyze',
      body: {'content': message},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Sentiment analysis failed');
  }

  // ── AI Chat ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendChatMessage(
    String message, {
    String provider = 'combined',
  }) async {
    final response = await _authPost(
      '/chat',
      body: {'message': message, 'provider': provider},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Chat failed');
  }

  Future<Map<String, dynamic>> getChatHistory() async {
    final response = await _authGet('/chat/history');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load chat history');
  }

  Future<void> clearChatHistory() async {
    final response = await _authDelete('/chat/history');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Failed to clear chat history');
    }
  }

  Future<Map<String, dynamic>> getChatProviders() async {
    final response = await _authGet('/chat/providers');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw _toApiException(response, fallback: 'Failed to load chat providers');
  }
}
