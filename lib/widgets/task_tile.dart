import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskTile extends StatefulWidget {
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
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final applyStrike = widget.strikeThroughWhenCompleted && t.completed;
    final hasSteps = t.steps.any((s) => s.trim().isNotEmpty);

    // Right-side controls + chevron
    final trailingControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Edit task',
          child: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: widget.onEdit,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: 'Delete task',
          child: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: t.completed ? 'Mark as not completed' : 'Mark as completed',
          child: IconButton(
            icon: Icon(t.completed ? Icons.check_circle : Icons.check_circle_outline),
            onPressed: widget.onToggle,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: _expanded ? 'Collapse' : 'Expand',
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: _expanded ? 0.5 : 0.0, // rotate chevron when expanded
            child: const Icon(Icons.expand_more),
          ),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        // Remove default trailing chevron spacing from ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          // We'll supply our own trailing (buttons + chevron)
          trailing: trailingControls,
          // We move the complete toggle to the right; no leading icon.
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

          title: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: applyStrike ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(_formatDisplayTime(t)),

          children: hasSteps
              ? <Widget>[
                  const SizedBox(height: 6),
                  ...t.steps
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
                ]
              : const <Widget>[],
        ),
      ),
    );
  }

  // Display like "11:45 pm – 12:15 am" with robust end-period inference,
  // including the 11 → 12 boundary you flagged.
  String _formatDisplayTime(Task t) {
    final start = t.startTime?.trim();
    final end   = t.endTime?.trim();
    final startPeriod = (t.period ?? '').trim().toUpperCase();

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
      if (startPeriod.isEmpty) return _fmt(start!);
      return '${_fmt(start!)} ${_lower(startPeriod)}';
    }
    if (!_valid(start) && _valid(end)) {
      if (startPeriod.isEmpty) return _fmt(end!);
      return '${_fmt(end!)} ${_lower(startPeriod)}';
    }

    // both valid
    final sHour = int.parse(start!.split(':')[0]); // 1..12
    final eHour = int.parse(end!.split(':')[0]);   // 1..12
    String endPeriod = startPeriod;

    // Robust period inference:
    // AM case:
    //  - if end hour == 12, it flips to PM (e.g., 11:30 AM -> 12:15 PM)
    //  - else if end hour < start hour, it also flips to PM (e.g., 10:30 AM -> 9:45 PM is unusual but respected)
    if (startPeriod == 'AM') {
      if (eHour == 12) {
        endPeriod = 'PM';
      } else if (eHour < sHour) {
        endPeriod = 'PM';
      }
    }

    // PM case:
    //  - if end hour == 12, it flips to AM (crossing midnight: 11:45 PM -> 12:15 AM)
    //  - else if end hour < start hour, also flips to AM (e.g., 10:30 PM -> 1:00 AM)
    if (startPeriod == 'PM') {
      if (eHour == 12) {
        endPeriod = 'AM';
      } else if (eHour < sHour) {
        endPeriod = 'AM';
      }
    }

    final left  = startPeriod.isEmpty ? _fmt(start) : '${_fmt(start)} ${_lower(startPeriod)}';
    final right = endPeriod.isEmpty   ? _fmt(end)   : '${_fmt(end)} ${_lower(endPeriod)}';
    return '$left – $right';
  }
}