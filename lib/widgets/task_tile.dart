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
            turns: _expanded ? 0.5 : 0.0,
            child: const Icon(Icons.expand_more),
          ),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          trailing: trailingControls,
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

  // Flip AM/PM ONLY if the interval crosses 12:00.
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

    int _to24(String hhmm, String period) {
      final parts = hhmm.split(':');
      final h12 = int.parse(parts[0]) % 12; // 12 -> 0
      final mm = int.parse(parts[1]);
      final add = (period == 'PM') ? 12 : 0;
      return (h12 + add) * 60 + mm; // minutes since midnight
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
    final s24 = _to24(start!, startPeriod);

    // Candidate 1: keep same period for end
    final endSame24 = _to24(end!, startPeriod);
    final sameForward = endSame24 >= s24;

    // Candidate 2: flip end period (AM <-> PM)
    final flipped = (startPeriod == 'AM') ? 'PM' : 'AM';
    final endFlip24 = _to24(end, flipped);
    final flipForward = endFlip24 >= s24;

    // Choose: prefer same-period if it's forward; otherwise flip if forward; else fall back to same.
    final endPeriod = sameForward
        ? startPeriod
        : (flipForward ? flipped : startPeriod);

    final left  = '${_fmt(start)} ${_lower(startPeriod)}';
    final right = '${_fmt(end)} ${_lower(endPeriod)}';
    return '$left – $right';
  }
}