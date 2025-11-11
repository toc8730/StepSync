import 'task.dart';

class RoutineTemplate {
  RoutineTemplate({
    required this.id,
    required this.title,
    this.description = '',
    required List<Task> tasks,
  }) : tasks = tasks.map(_cloneTask).toList();

  final String id;
  final String title;
  final String description;
  final List<Task> tasks;

  RoutineTemplate copyWith({
    String? id,
    String? title,
    String? description,
    List<Task>? tasks,
  }) {
    return RoutineTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      tasks: tasks ?? this.tasks.map(_cloneTask).toList(),
    );
  }

  List<Task> cloneTasks() => tasks.map(_cloneTask).toList();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'tasks': tasks.map(_taskToJson).toList(),
    };
  }

  factory RoutineTemplate.fromJson(Map<String, dynamic> json) {
    final tasksRaw = json['tasks'];
    final taskList = (tasksRaw is List)
        ? tasksRaw
            .whereType<Map>()
            .map((item) => _taskFromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <Task>[];
    return RoutineTemplate(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      tasks: taskList,
    );
  }
}

Task _cloneTask(Task task) {
  return Task(
    title: task.title,
    steps: List<String>.from(task.steps),
    startTime: task.startTime,
    endTime: task.endTime,
    period: task.period,
    hidden: task.hidden,
    completed: task.completed,
    familyTag: task.familyTag,
    scheduledDate: task.scheduledDate,
  );
}

Map<String, dynamic> _taskToJson(Task task) {
  return {
    'title': task.title,
    'steps': task.steps,
    'startTime': task.startTime,
    'endTime': task.endTime,
    'period': task.period,
    'hidden': task.hidden,
    'completed': task.completed,
    'familyTag': task.familyTag,
    'scheduledDate': task.scheduledDate,
  };
}

Task _taskFromJson(Map<String, dynamic> json) {
  return Task(
    title: (json['title'] ?? '').toString(),
    steps: (json['steps'] is List)
        ? (json['steps'] as List).map((s) => s?.toString() ?? '').toList()
        : const <String>[],
    startTime: (json['startTime'] ?? '').toString().isEmpty ? null : json['startTime'] as String,
    endTime: (json['endTime'] ?? '').toString().isEmpty ? null : json['endTime'] as String,
    period: (json['period'] ?? '').toString().isEmpty ? null : json['period'] as String,
    hidden: json['hidden'] == true,
    completed: json['completed'] == true,
    familyTag: (json['familyTag'] ?? '').toString().isEmpty ? null : json['familyTag'] as String,
    scheduledDate: (json['scheduledDate'] ?? '').toString().isEmpty ? null : json['scheduledDate'] as String,
  );
}
