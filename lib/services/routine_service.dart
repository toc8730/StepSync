import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../data/globals.dart';
import '../models/routine_template.dart';
import '../models/task.dart';

class RoutineService {
  static const _base = BackendConfig.baseUrl;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  static Future<List<RoutineTemplate>> fetchRoutines() async {
    final res = await http.get(Uri.parse('$_base/routines'), headers: _headers());
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res) ?? 'Unable to load routines (${res.statusCode}).');
    }
    final body = json.decode(res.body);
    final list = body['routines'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((item) => RoutineTemplate.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<RoutineTemplate> saveRoutine({
    String? routineId,
    required String title,
    String description = '',
    required List<Task> tasks,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'description': description,
      'tasks': tasks.map(_taskToJson).toList(),
    };
    final uri = routineId == null ? Uri.parse('$_base/routines') : Uri.parse('$_base/routines/$routineId');
    final res = await (routineId == null
        ? http.post(uri, headers: _headers(), body: json.encode(payload))
        : http.put(uri, headers: _headers(), body: json.encode(payload)));
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res) ?? 'Unable to save routine (${res.statusCode}).');
    }
    final body = json.decode(res.body);
    if (body is! Map || body['routine'] is! Map) {
      throw Exception('Malformed routine response.');
    }
    return RoutineTemplate.fromJson(Map<String, dynamic>.from(body['routine'] as Map));
  }

  static Future<void> deleteRoutine(String routineId) async {
    final res = await http.delete(Uri.parse('$_base/routines/$routineId'), headers: _headers());
    if (res.statusCode == 200) return;
    if (res.statusCode == 404) {
      throw Exception('Routine not found.');
    }
    throw Exception(_errorMessage(res) ?? 'Unable to delete routine (${res.statusCode}).');
  }

  static Map<String, dynamic> _taskToJson(Task task) {
    return {
      'title': task.title,
      'steps': task.steps,
      'startTime': task.startTime,
      'endTime': task.endTime,
      'period': task.period,
      'hidden': task.hidden,
      'completed': task.completed,
      'familyTag': task.familyTag,
    };
  }

  static String? _errorMessage(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }
}
