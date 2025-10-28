import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/task_step.dart';
import '../widgets/media_picker.dart';

class TaskTile extends StatefulWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    this.onEdit,
    this.onDelete,
    this.strikeThroughWhenCompleted = true,
    this.stepsWithImages = const <TaskStep>[],
    this.onOpen,
    this.readOnly = false, // <- NEW
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool strikeThroughWhenCompleted;
  final List<TaskStep> stepsWithImages;
  final VoidCallback? onOpen;
  final bool readOnly;

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
        if (!widget.readOnly && widget.onEdit != null)
          Tooltip(
            message: 'Edit task',
            child: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: widget.onEdit,
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (!widget.readOnly && widget.onDelete != null)
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
        if (widget.onOpen != null)
          Tooltip(
            message: 'Open details',
            child: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: widget.onOpen,
              visualDensity: VisualDensity.compact,
            ),
          ),
        const SizedBox(width: 6),
        Tooltip(
          message: _expanded ? 'Collapse' : 'Expand',
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              turns: _expanded ? 0.5 : 0.0,
              child: const Icon(Icons.expand_more),
            ),
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
                      .asMap()
                      .entries
                      .where((e) => e.value.trim().isNotEmpty)
                      .map((entry) {
                    final i = entry.key;
                    final s = entry.value.trim();

                    final imgs = (i < widget.stepsWithImages.length)
                        ? widget.stepsWithImages[i].images
                        : const <PickedImage>[];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(child: Text(s)),
                            ],
                          ),
                          if (imgs.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: imgs.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                              ),
                              itemBuilder: (_, j) => ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  imgs[j].bytes,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ]
              : const <Widget>[],
        ),
      ),
    );
  }

  String _formatDisplayTime(Task t) {
    final start = t.startTime?.trim();
    final end = t.endTime?.trim();
    final startPeriod = (t.period ?? '').trim().toUpperCase();

    bool valid(String? hhmm) {
      if (hhmm == null || hhmm.isEmpty) return false;
      final re = RegExp(r'^(?:[1-9]|1[0-2]):[0-5][0-9]$');
      return re.hasMatch(hhmm);
    }

    String lower(String p) => p.toLowerCase();

    String fmt(String hhmm) {
      final parts = hhmm.split(':');
      final h = int.parse(parts[0]);
      final mm = parts[1].padLeft(2, '0');
      return (mm == '00') ? '$h' : '$h:$mm';
    }

    int to24(String hhmm, String period) {
      final parts = hhmm.split(':');
      final h12 = int.parse(parts[0]) % 12;
      final mm = int.parse(parts[1]);
      final add = (period == 'PM') ? 12 : 0;
      return (h12 + add) * 60 + mm;
    }

    if (!valid(start) && !valid(end)) return '';
    if (valid(start) && !valid(end)) {
      if (startPeriod.isEmpty) return fmt(start!);
      return '${fmt(start!)} ${lower(startPeriod)}';
    }
    if (!valid(start) && valid(end)) {
      if (startPeriod.isEmpty) return fmt(end!);
      return '${fmt(end!)} ${lower(startPeriod)}';
    }

    final s24 = to24(start!, startPeriod);
    final endSame24 = to24(end!, startPeriod);
    final sameForward = endSame24 >= s24;
    final flipped = (startPeriod == 'AM') ? 'PM' : 'AM';
    final endFlip24 = to24(end, flipped);
    final flipForward = endFlip24 >= s24;
    final endPeriod = sameForward ? startPeriod : (flipForward ? flipped : startPeriod);

    final left = '${fmt(start)} ${lower(startPeriod)}';
    final right = '${fmt(end)} ${lower(endPeriod)}';
    return '$left – $right';
  }
}