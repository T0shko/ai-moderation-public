import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  final String baseUrl = "http://localhost:8080/api";

  // ── Auth token helpers ──────────────────────────────────────────

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
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

  Map<String, String> _authHeaders(String token) => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $token",
  };

  // ── Authentication ──────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signin'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to login');
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
    throw Exception('Failed to register');
  }

  // ── Comments ────────────────────────────────────────────────────

  Future<List<dynamic>> getComments() async {
    final response = await http.get(Uri.parse('$baseUrl/comments'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load comments');
  }

  Future<void> postComment(String content) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/comments'),
      headers: _authHeaders(token!),
      body: jsonEncode({"content": content}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to post comment');
    }
  }

  Future<List<dynamic>> getPendingComments() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/comments/pending'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load pending comments');
  }

  Future<void> moderateComment(int id, bool approved) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/comments/$id/moderate?approved=$approved'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to moderate comment');
    }
  }

  // ── Admin ───────────────────────────────────────────────────────

  Future<List<dynamic>> getUsers() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load users');
  }

  Future<void> updateUserRole(int userId, String role) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users/$userId/role?role=$role'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update role');
    }
  }

  Future<Map<String, dynamic>> getAiSettings() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/admin/ai-settings'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load AI settings');
  }

  Future<void> updateAiSettings(double threshold, String activeModel) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/ai-settings'),
      headers: _authHeaders(token!),
      body: jsonEncode({"threshold": threshold, "activeModel": activeModel}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update AI settings');
    }
  }

  Future<List<dynamic>> getAllCommentsAdmin() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/admin/comments'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load all comments');
  }

  // ── Image moderation ────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadImage(
    List<int> imageBytes,
    String filename,
  ) async {
    final token = await getToken();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/moderation/images/upload'),
    );
    request.headers['Authorization'] = 'Bearer $token';

    String contentType = 'image/jpeg';
    if (filename.toLowerCase().endsWith('.png')) {
      contentType = 'image/png';
    } else if (filename.toLowerCase().endsWith('.gif')) {
      contentType = 'image/gif';
    } else if (filename.toLowerCase().endsWith('.webp')) {
      contentType = 'image/webp';
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(
      'Image moderation failed (${response.statusCode}): ${response.body}',
    );
  }

  Future<Map<String, dynamic>> getImageModerationStats() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/moderation/images/stats'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load image stats');
  }

  /// Test message sentiment analysis
  Future<Map<String, dynamic>> testSentiment(String message) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/comments/test-analyze'),
      headers: _authHeaders(token!),
      body: jsonEncode({"content": message}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Sentiment analysis failed');
  }

  // ── AI Chat ─────────────────────────────────────────────────────

  /// Send a message to the AI chatbot
  /// [provider] can be "huggingface", "opennlp", or "combined"
  Future<Map<String, dynamic>> sendChatMessage(
    String message, {
    String provider = 'combined',
  }) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/chat'),
      headers: _authHeaders(token!),
      body: jsonEncode({"message": message, "provider": provider}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Chat failed (${response.statusCode}): ${response.body}');
  }

  /// Get conversation history
  Future<Map<String, dynamic>> getChatHistory() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/chat/history'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load chat history');
  }

  /// Clear conversation history
  Future<void> clearChatHistory() async {
    final token = await getToken();
    final response = await http.delete(
      Uri.parse('$baseUrl/chat/history'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to clear chat history');
    }
  }

  /// Get available AI providers
  Future<Map<String, dynamic>> getChatProviders() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/chat/providers'),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load chat providers');
  }
}
