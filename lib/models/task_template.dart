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
}