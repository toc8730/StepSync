import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/globals.dart';
import '../models/task.dart';

/// Lightweight client that talks to the Flask backend to transform a natural
/// language prompt into concrete `Task` objects usable by the UI.
class AiTaskGenerator {
  static const String _baseUrl = 'http://127.0.0.1:5000';

  /// Ask the backend to generate tasks for a natural-language [prompt].
  static Future<List<Task>> fromPrompt(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      throw Exception('Prompt cannot be empty.');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/ai/tasks'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      },
      body: json.encode({'prompt': trimmed}),
    );

    if (response.statusCode != 200) {
      final message = _errorMessage(response.body) ??
          'AI request failed (${response.statusCode}).';
      throw Exception(message);
    }

    final decoded = json.decode(response.body);
    final List<dynamic> list =
        (decoded is Map && decoded['tasks'] is List) ? decoded['tasks'] as List : const [];
    return list.map<Task>(_decodeTask).where((task) => task.title.trim().isNotEmpty).toList();
  }

  static Task _decodeTask(dynamic raw) {
    final map = (raw is Map) ? raw : const <String, dynamic>{};

    final steps = (map['steps'] is List)
        ? (map['steps'] as List)
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : const <String>[];

    return Task(
      title: (map['title'] ?? '').toString(),
      steps: steps,
      startTime: _stringOrNull(map['startTime']),
      endTime: _stringOrNull(map['endTime']),
      period: _normalizePeriod(map['period']),
      completed: (map['completed'] is bool) ? map['completed'] as bool : false,
      hidden: (map['hidden'] is bool) ? map['hidden'] as bool : false,
    );
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _normalizePeriod(dynamic value) {
    final text = value?.toString().trim().toUpperCase();
    if (text == 'PM') return 'PM';
    if (text == 'AM') return 'AM';
    return null;
  }

  static String? _errorMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // ignore decode errors, fall back to generic string
    }
    return null;
  }
}
