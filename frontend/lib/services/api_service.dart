import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Custom exception for authentication failures.
/// Screens catch this to trigger navigation to login.
class AuthException implements Exception {
  final String message;
  AuthException([this.message = 'Session expired. Please log in again.']);
  @override
  String toString() => message;
}

class ApiService {
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

  // ── Auth token helpers ──────────────────────────────────────────

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// Returns the token or throws [AuthException] + redirects to login.
  Future<String> _requireToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      await _forceLogout();
      throw AuthException();
    }
    return token;
  }

  Future<void> saveToken(
    String token,
    String username,
    List<String> roles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    await prefs.setStringList('roles', roles);
  }

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  Future<List<String>> getRoles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('roles') ?? [];
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Clears stored credentials and navigates to login screen.
  Future<void> _forceLogout() async {
    await logout();
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  // ── Centralized HTTP helpers (auth-aware) ───────────────────────

  Map<String, String> _jsonAuth(String token) => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $token",
  };

  Map<String, String> _bearerOnly(String token) => {
    "Authorization": "Bearer $token",
  };

  /// Authenticated GET – handles 401 globally.
  Future<http.Response> _authGet(String path) async {
    final token = await _requireToken();
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: _bearerOnly(token),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _forceLogout();
      throw AuthException();
    }
    return response;
  }

  /// Authenticated POST (JSON body) – handles 401 globally.
  Future<http.Response> _authPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _jsonAuth(token),
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _forceLogout();
      throw AuthException();
    }
    return response;
  }

  /// Authenticated DELETE – handles 401 globally.
  Future<http.Response> _authDelete(String path) async {
    final token = await _requireToken();
    final response = await http.delete(
      Uri.parse('$baseUrl$path'),
      headers: _bearerOnly(token),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _forceLogout();
      throw AuthException();
    }
    return response;
  }

  // ── Authentication (public, no token needed) ────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/signin'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );
    } catch (e) {
      throw Exception('Cannot connect to server. Is the backend running?');
    }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 401) {
      throw Exception('Invalid username or password');
    }
    // Parse error message from server if available
    try {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? body['message'] ?? 'Login failed');
    } catch (e) {
      if (e.toString().contains('Login failed') ||
          e.toString().contains('Invalid') ||
          e.toString().contains('Cannot connect') ||
          e.toString().contains('Authentication')) {
        rethrow;
      }
      throw Exception('Login failed (${response.statusCode})');
    }
  }

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Registration failed');
  }

  // ── Comments ────────────────────────────────────────────────────

  Future<List<dynamic>> getComments() async {
    // Public endpoint – no auth required
    final response = await http.get(Uri.parse('$baseUrl/comments'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load comments');
  }

  Future<void> postComment(String content) async {
    final response = await _authPost('/comments', body: {"content": content});
    if (response.statusCode != 200) {
      throw Exception('Failed to post comment');
    }
  }

  Future<List<dynamic>> getPendingComments() async {
    final response = await _authGet('/comments/pending');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load pending comments');
  }

  Future<void> moderateComment(int id, bool approved) async {
    final response = await _authPost(
      '/comments/$id/moderate?approved=$approved',
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to moderate comment');
    }
  }

  // ── Admin ───────────────────────────────────────────────────────

  Future<List<dynamic>> getUsers() async {
    final response = await _authGet('/admin/users');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load users');
  }

  Future<void> updateUserRole(int userId, String role) async {
    final response = await _authPost('/admin/users/$userId/role?role=$role');
    if (response.statusCode != 200) {
      throw Exception('Failed to update role');
    }
  }

  Future<Map<String, dynamic>> getAiSettings() async {
    final response = await _authGet('/admin/ai-settings');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load AI settings');
  }

  Future<void> updateAiSettings(double threshold, String activeModel) async {
    final response = await _authPost(
      '/admin/ai-settings',
      body: {"threshold": threshold, "activeModel": activeModel},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update AI settings');
    }
  }

  Future<List<dynamic>> getAllCommentsAdmin() async {
    final response = await _authGet('/admin/comments');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load all comments');
  }

  // ── Vision Lab ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getVisionLabInfo() async {
    final response = await http.get(Uri.parse('$baseUrl/vision-lab'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load vision lab info');
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
        headers: {
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
      throw Exception(
        'Could not connect to the vision lab. Check that the backend is running.',
      );
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    if (response.statusCode == 400 || response.statusCode == 405) {
      try {
        final body = jsonDecode(response.body);
        throw Exception(
          body['message'] ?? body['error'] ?? 'Vision lab request failed',
        );
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }

    if (response.statusCode == 413) {
      throw Exception('Image is too large. Maximum size is 10 MB.');
    }

    throw Exception(
      'Vision lab request failed (error ${response.statusCode}). Please try again.',
    );
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
      body: {"content": message},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Sentiment analysis failed');
  }

  // ── AI Chat ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendChatMessage(
    String message, {
    String provider = 'combined',
  }) async {
    final response = await _authPost(
      '/chat',
      body: {"message": message, "provider": provider},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Chat failed (${response.statusCode}): ${response.body}');
  }

  Future<Map<String, dynamic>> getChatHistory() async {
    final response = await _authGet('/chat/history');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load chat history');
  }

  Future<void> clearChatHistory() async {
    final response = await _authDelete('/chat/history');
    if (response.statusCode != 200) {
      throw Exception('Failed to clear chat history');
    }
  }

  Future<Map<String, dynamic>> getChatProviders() async {
    final response = await _authGet('/chat/providers');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load chat providers');
  }
}
