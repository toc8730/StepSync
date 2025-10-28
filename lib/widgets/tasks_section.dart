import 'package:flutter/material.dart';
import '../task_controller.dart';
import '../widgets/task_tile.dart';
import '../widgets/task_editor_dialog.dart';
import '../widgets/step_viewer_dialog.dart';
import '../data/images_repo.dart';

class TasksSection extends StatelessWidget {
  const TasksSection({
    super.key,
    required this.ctrl,
    this.readOnly = false,
  });

  final TaskController ctrl;
  final bool readOnly; // child => true

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _header(context, 'Earlier Today', 'Before now', ctrl.earlierToday.length, Icons.wb_sunny_outlined),
        ..._buildList(context, ctrl.earlierToday, strikeThroughWhenCompleted: true),

        const SizedBox(height: 12),
        _header(context, 'Later Today', 'After now', ctrl.laterToday.length, Icons.nights_stay_outlined),
        ..._buildList(context, ctrl.laterToday, strikeThroughWhenCompleted: true),

        const SizedBox(height: 12),
        _header(context, 'Completed Tasks', 'Done today', ctrl.completed.length, Icons.check_circle),
        ..._buildList(context, ctrl.completed, strikeThroughWhenCompleted: false),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _header(BuildContext c, String title, String subtitle, int count, IconData icon) {
    final color = Theme.of(c).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  subtitle,
                  style: Theme.of(c).textTheme.bodySmall?.copyWith(
                        color: Theme.of(c).colorScheme.onSurface.withOpacity(0.65),
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
            child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildList(BuildContext context, List items, {required bool strikeThroughWhenCompleted}) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No tasks here.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          ),
        )
      ];
    }
    return [
      const SizedBox(height: 8),
      ...List.generate(items.length, (i) {
        final t = items[i];
        final stepImages = ImagesRepo.I.get(t, t.steps.length); // per-step images

        return TaskTile(
          task: t,
          readOnly: readOnly,
          stepsImageBytes: stepImages,
          strikeThroughWhenCompleted: strikeThroughWhenCompleted,
          onToggle: () {
            final idx = ctrl.all.indexOf(t);
            if (idx != -1) ctrl.toggleCompleted(idx);
          },
          onEdit: readOnly
              ? null
              : () async {
                  final idx = ctrl.all.indexOf(t);
                  if (idx == -1) return;
                  final edited = await TaskEditorDialog.show(context, initial: t);
                  if (edited != null) ctrl.update(idx, edited);
                },
          onDelete: readOnly
              ? null
              : () {
                  final idx = ctrl.all.indexOf(t);
                  if (idx != -1) ctrl.removeAt(idx);
                },
          onOpen: () async {
            await StepViewerDialog.show(context, task: t);
            // After dialog closes, images may have changed. Trigger a rebuild:
            // (If your controller exposes notifyListeners internally, the next setState above will refresh the list anyway.)
            (context as Element).markNeedsBuild();
          },
        );
      }),
    ];
  }
}