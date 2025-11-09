// lib/models/task_template.dart
import '../models/task.dart';

/// Lightweight template that can produce a Task prefilled with
/// title, optional steps, and optional time window.
class TaskTemplate {
  final String id;
  final String title;
  final List<String> steps;

  /// Times are 12h "H:MM" strings (e.g. "8:00"). Period must be "AM" or "PM".
  final String? start;
  final String? end;
  final String? period;

  const TaskTemplate({
    required this.id,
    required this.title,
    this.steps = const [],
    this.start,
    this.end,
    this.period,
  });

  Task toTask() {
    return Task(
      title: title,
      steps: List<String>.from(steps),
      startTime: start,
      endTime: end,
      period: period ?? 'AM',
      completed: false,
      hidden: false,
    );
  }

  factory TaskTemplate.fromJson(Map<String, dynamic> json) {
    List<String> parsedSteps = const <String>[];
    if (json['steps'] is List) {
      parsedSteps = (json['steps'] as List)
          .map((step) => step == null ? '' : step.toString())
          .where((step) => step.trim().isNotEmpty)
          .cast<String>()
          .toList();
    }

    String? cleanValue(Object? value, {bool uppercase = false}) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) return null;
      return uppercase ? text.toUpperCase() : text;
    }

    return TaskTemplate(
      id: (json['id'] ?? json['template_id'] ?? json['slug'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      steps: parsedSteps,
      start: cleanValue(json['start'] ?? json['start_time']),
      end: cleanValue(json['end'] ?? json['end_time']),
      period: cleanValue(json['period'], uppercase: true),
    );
  }
}
