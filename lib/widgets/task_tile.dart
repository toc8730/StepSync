import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    this.onEdit,
    this.onDelete,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: IconButton(
          icon: Icon(task.completed ? Icons.check_circle : Icons.check_circle_outline),
          tooltip: task.completed ? 'Mark as not completed' : 'Mark as completed',
          onPressed: onToggle,
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: task.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          [
            if (task.startTime != null) task.startTime!,
            if (task.endTime != null) '– ${task.endTime!}',
            if (task.period != null) ' ${task.period!}',
          ].join(''),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null) IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
            if (onDelete != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}