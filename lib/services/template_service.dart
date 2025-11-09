import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../data/globals.dart';
import '../models/task.dart';
import '../models/task_template.dart';

class SavedTemplate {
  const SavedTemplate({
    required this.id,
    required this.template,
    required this.scope,
    required this.owner,
    required this.canEdit,
    required this.canDelete,
    required this.sharedWithFamily,
  });

  final String id;
  final TaskTemplate template;
  final String scope; // personal | family
  final String owner;
  final bool canEdit;
  final bool canDelete;
  final bool sharedWithFamily;

  factory SavedTemplate.fromJson(Map<String, dynamic> json) {
    final tmpl = TaskTemplate.fromJson(json);
    final scope = (json['scope'] ?? '').toString();
    return SavedTemplate(
      id: json['id']?.toString() ?? tmpl.id,
      template: tmpl,
      scope: scope,
      owner: json['owner']?.toString() ?? '',
      canEdit: json['can_edit'] == true,
      canDelete: json['can_delete'] == true,
      sharedWithFamily: json['shared_with_family'] == true,
    );
  }
}

class TemplateFetchResult {
  const TemplateFetchResult({required this.personal, required this.family});

  final List<SavedTemplate> personal;
  final List<SavedTemplate> family;
}

class TemplateService {
  static const String _base = BackendConfig.baseUrl;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  static List<SavedTemplate> _parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => SavedTemplate.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<TemplateFetchResult> fetchTemplates() async {
    final res = await http.get(Uri.parse('$_base/templates'), headers: _headers());
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res) ?? 'Unable to load templates (${res.statusCode}).');
    }
    final body = json.decode(res.body);
    return TemplateFetchResult(
      personal: _parseList(body['personal']),
      family: _parseList(body['family']),
    );
  }

  static Future<SavedTemplate> createTemplate({
    required Task task,
    bool shareWithFamily = false,
  }) async {
    final payload = <String, dynamic>{
      'title': task.title.trim(),
      'steps': List<String>.from(task.steps),
      if ((task.startTime ?? '').isNotEmpty) 'start': task.startTime,
      if ((task.endTime ?? '').isNotEmpty) 'end': task.endTime,
      if ((task.period ?? '').isNotEmpty) 'period': task.period,
      if (shareWithFamily) 'share_with_family': true,
    };
    final res = await http.post(
      Uri.parse('$_base/templates'),
      headers: _headers(),
      body: json.encode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res) ?? 'Unable to save template (${res.statusCode}).');
    }
    final body = json.decode(res.body);
    if (body is! Map || body['template'] is! Map) {
      throw Exception('Malformed template response.');
    }
    return SavedTemplate.fromJson(Map<String, dynamic>.from(body['template'] as Map));
  }

  static Future<SavedTemplate> updateTemplate({
    required String templateId,
    required Task task,
  }) async {
    final payload = <String, dynamic>{
      'title': task.title.trim(),
      'steps': List<String>.from(task.steps),
      if ((task.startTime ?? '').isNotEmpty) 'start': task.startTime,
      if ((task.endTime ?? '').isNotEmpty) 'end': task.endTime,
      if ((task.period ?? '').isNotEmpty) 'period': task.period,
    };
    final res = await http.put(
      Uri.parse('$_base/templates/$templateId'),
      headers: _headers(),
      body: json.encode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res) ?? 'Unable to update template (${res.statusCode}).');
    }
    final body = json.decode(res.body);
    if (body is! Map || body['template'] is! Map) {
      throw Exception('Malformed template response.');
    }
    return SavedTemplate.fromJson(Map<String, dynamic>.from(body['template'] as Map));
  }

  static Future<void> deleteTemplate(String templateId) async {
    final res = await http.delete(
      Uri.parse('$_base/templates/$templateId'),
      headers: _headers(),
    );
    if (res.statusCode == 200) return;
    if (res.statusCode == 404) {
      throw Exception('Template not found or already deleted.');
    }
    throw Exception(_errorMessage(res) ?? 'Unable to delete template (${res.statusCode}).');
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
