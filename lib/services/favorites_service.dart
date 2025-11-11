import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../data/globals.dart';

class FavoritesData {
  FavoritesData({
    required this.templateIds,
    required this.routineIds,
  });

  final Set<String> templateIds;
  final Set<String> routineIds;

  factory FavoritesData.fromJson(Map<String, dynamic> json) {
    Set<String> _parse(dynamic value) {
      if (value is List) {
        return value.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toSet();
      }
      return <String>{};
    }

    return FavoritesData(
      templateIds: _parse(json['templates']),
      routineIds: _parse(json['routines']),
    );
  }
}

class FavoritesService {
  static const String _base = BackendConfig.baseUrl;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  static Future<FavoritesData> fetchFavorites() async {
    final res = await http.get(Uri.parse('$_base/favorites'), headers: _headers());
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res.body) ?? 'Failed to load favorites (${res.statusCode}).');
    }
    final decoded = json.decode(res.body) as Map<String, dynamic>;
    return FavoritesData.fromJson(decoded);
  }

  static Future<FavoritesData> updateTemplates(Set<String> templateIds) {
    return _update(templates: templateIds);
  }

  static Future<FavoritesData> updateRoutines(Set<String> routineIds) {
    return _update(routines: routineIds);
  }

  static Future<FavoritesData> _update({Set<String>? templates, Set<String>? routines}) async {
    final body = <String, dynamic>{};
    if (templates != null) {
      body['templates'] = templates.toList();
    }
    if (routines != null) {
      body['routines'] = routines.toList();
    }
    if (body.isEmpty) {
      throw Exception('Nothing to update.');
    }

    final res = await http.post(
      Uri.parse('$_base/favorites'),
      headers: _headers(),
      body: json.encode(body),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res.body) ?? 'Failed to update favorites (${res.statusCode}).');
    }
    final decoded = json.decode(res.body) as Map<String, dynamic>;
    return FavoritesData.fromJson(decoded);
  }

  static String? _errorMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }
}
