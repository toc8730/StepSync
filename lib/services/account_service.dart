import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../data/globals.dart';

class AccountUpdateResponse {
  const AccountUpdateResponse({this.username, this.email, this.token});

  final String? username;
  final String? email;
  final String? token;

  factory AccountUpdateResponse.fromJson(Map<String, dynamic> json) {
    String? clean(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return AccountUpdateResponse(
      username: clean(json['username']?.toString()),
      email: clean(json['email']?.toString()),
      token: clean(json['token']?.toString()),
    );
  }
}

class AccountService {
  static const String _baseUrl = BackendConfig.baseUrl;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  static Future<AccountUpdateResponse> updateCredentials({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
    String? confirmPassword,
  }) async {
    final payload = <String, String>{
      'current_password': currentPassword,
      if (newUsername != null && newUsername.trim().isNotEmpty) 'new_username': newUsername.trim(),
      if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
      if (confirmPassword != null && confirmPassword.isNotEmpty) 'confirm_password': confirmPassword,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/account/credentials'),
      headers: _headers(),
      body: json.encode(payload),
    );

    return _mapResponse(response, context: 'update credentials');
  }

  static Future<AccountUpdateResponse> switchGoogleAccount({
    required String currentPassword,
    required String idToken,
  }) async {
    final payload = <String, String>{
      'current_password': currentPassword,
      'id_token': idToken,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/account/google/switch'),
      headers: _headers(),
      body: json.encode(payload),
    );

    return _mapResponse(response, context: 'switch Google account');
  }

  static AccountUpdateResponse _mapResponse(http.Response response, {required String context}) {
    Map<String, dynamic>? body;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    } catch (_) {}

    if (response.statusCode != 200 || body == null) {
      final error = _errorMessage(body) ??
          'Unable to $context (${response.statusCode}).';
      throw Exception(error);
    }

    return AccountUpdateResponse.fromJson(body);
  }

  static String? _errorMessage(Map<String, dynamic>? body) {
    final raw = body?['error'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }
}
