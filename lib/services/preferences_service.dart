import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/globals.dart';

class PreferencesService {
  static const String _baseUrl = 'http://127.0.0.1:5000';

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  static Future<String?> fetchTheme() async {
    final res = await http.get(Uri.parse('$_baseUrl/profile/preferences'), headers: _headers());
    if (res.statusCode != 200) return null;
    final body = json.decode(res.body);
    if (body is Map && body['preferences'] is Map && body['preferences']['theme'] is String) {
      return (body['preferences']['theme'] as String).toLowerCase();
    }
    return null;
  }

  static Future<bool> updateTheme(String theme) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/profile/preferences'),
      headers: _headers(),
      body: json.encode({'theme': theme}),
    );
    return res.statusCode == 200;
  }
}
