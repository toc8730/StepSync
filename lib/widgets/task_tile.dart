import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    this.onEdit,
    this.onDelete,
    this.strikeThroughWhenCompleted = true,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool strikeThroughWhenCompleted;

  @override
  Widget build(BuildContext context) {
    final applyStrike = strikeThroughWhenCompleted && task.completed;
    final hasSteps = task.steps.any((s) => s.trim().isNotEmpty);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

        leading: IconButton(
          icon: Icon(task.completed ? Icons.check_circle : Icons.check_circle_outline),
          tooltip: task.completed ? 'Mark as not completed' : 'Mark as completed',
          onPressed: onToggle,
        ),

        title: Text(
          task.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: applyStrike ? TextDecoration.lineThrough : null,
          ),
        ),

        subtitle: Text(_formatDisplayTime(task)),

        children: hasSteps
            ? <Widget>[
                const SizedBox(height: 6),
                ...task.steps
                    .where((s) => s.trim().isNotEmpty)
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(child: Text(s.trim())),
                            ],
                          ),
                        )),
                if (onEdit != null || onDelete != null) ...[
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onEdit != null)
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                        ),
                      if (onDelete != null) const SizedBox(width: 8),
                      if (onDelete != null)
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ]
            : const <Widget>[],
      ),
    );
  }

  // Display like "11 am – 1 pm" with smart end-period inference.
  String _formatDisplayTime(Task t) {
    final start = t.startTime?.trim();
    final end   = t.endTime?.trim();
    final period = (t.period ?? '').trim().toUpperCase();

    bool _valid(String? hhmm) {
      if (hhmm == null || hhmm.isEmpty) return false;
      final re = RegExp(r'^(?:[1-9]|1[0-2]):[0-5][0-9]$');
      return re.hasMatch(hhmm);
    }

    String _lower(String p) => p.toLowerCase();

    String _fmt(String hhmm) {
      final parts = hhmm.split(':');
      final h = int.parse(parts[0]);
      final mm = parts[1].padLeft(2, '0');
      return (mm == '00') ? '$h' : '$h:$mm';
    }

    if (!_valid(start) && !_valid(end)) return '';
    if (_valid(start) && !_valid(end)) {
      if (period.isEmpty) return _fmt(start!);
      return '${_fmt(start!)} ${_lower(period)}';
    }
    if (!_valid(start) && _valid(end)) {
      if (period.isEmpty) return _fmt(end!);
      return '${_fmt(end!)} ${_lower(period)}';
    }

    // both valid
    final sHour = int.parse(start!.split(':')[0]); // 1..12
    final eHour = int.parse(end!.split(':')[0]);   // 1..12
    String endPeriod = period;
    if (period == 'AM' && eHour < sHour) {
      endPeriod = 'PM';
    }
    final left  = period.isEmpty ? _fmt(start) : '${_fmt(start)} ${_lower(period)}';
    final right = endPeriod.isEmpty ? _fmt(end) : '${_fmt(end)} ${_lower(endPeriod)}';
    return '$left – $right';
  }
}