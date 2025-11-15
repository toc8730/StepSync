import 'package:flutter/material.dart';

import '../models/task.dart';
import '../widgets/task_editor_dialog.dart';
import '../widgets/template_picker_dialog.dart';

enum RoutineEditorOutcome { saveRoutine, deploy }

class RoutineEditorResult {
  RoutineEditorResult({
    required this.outcome,
    required this.name,
    required List<Task> tasks,
    this.routineId,
  }) : tasks = tasks.map(_cloneTask).toList();

  final RoutineEditorOutcome outcome;
  final String name;
  final List<Task> tasks;
  final String? routineId;
}

class RoutineEditorPage extends StatefulWidget {
  const RoutineEditorPage({
    super.key,
    required this.initialTasks,
    this.initialName = '',
    this.title = 'Routine Builder',
    this.showSaveButton = true,
    this.showDeployButton = false,
    this.existingRoutineId,
  });

  final List<Task> initialTasks;
  final String initialName;
  final String title;
  final bool showSaveButton;
  final bool showDeployButton;
  final String? existingRoutineId;

  static Future<RoutineEditorResult?> open(
    BuildContext context, {
    required List<Task> tasks,
    String initialName = '',
    String title = 'Routine Builder',
    bool showSaveButton = true,
    bool showDeployButton = false,
    String? existingRoutineId,
  }) {
    return Navigator.of(context).push<RoutineEditorResult?>(
      MaterialPageRoute(
        builder: (_) => RoutineEditorPage(
          initialTasks: tasks,
          initialName: initialName,
          title: title,
          showSaveButton: showSaveButton,
          showDeployButton: showDeployButton,
          existingRoutineId: existingRoutineId,
        ),
      ),
    );
  }

  @override
  State<RoutineEditorPage> createState() => _RoutineEditorPageState();
}

class _RoutineEditorPageState extends State<RoutineEditorPage> {
  late final TextEditingController _nameCtrl;
  late List<Task> _tasks;
  final bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _tasks = <Task>[];
    for (final task in widget.initialTasks) {
      _insertTask(_cloneTask(task));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Routine name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add task'),
                  onPressed: _busy ? null : _addTaskManually,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Add from premade'),
                  onPressed: _busy ? null : _addFromTemplate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _tasks.isEmpty
                ? const Center(child: Text('No tasks yet. Add one to start building your routine.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return _RoutineTaskCard(
                        key: ValueKey('$index-${task.title}-${task.startTime}'),
                        task: task,
                        onEdit: _busy ? null : () => _editTask(index),
                        onDelete: _busy ? null : () => _deleteTask(index),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  if (widget.showSaveButton)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _finish(RoutineEditorOutcome.saveRoutine),
                        child: const Text('Save as routine'),
                      ),
                    ),
                  if (widget.showSaveButton && widget.showDeployButton) const SizedBox(width: 12),
                  if (widget.showDeployButton)
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _finish(RoutineEditorOutcome.deploy),
                        child: const Text('Deploy today'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTaskManually() async {
    final Task? task = await TaskEditorDialog.show(context);
    if (task == null) return;
    setState(() => _insertTask(task));
  }

  Future<void> _addFromTemplate() async {
    final Task? templated = await TemplatePickerDialog.pickAndEdit(
      context,
      canShareWithFamily: false,
    );
    if (templated == null) return;
    setState(() => _insertTask(templated));
  }

  Future<void> _editTask(int index) async {
    final Task original = _tasks[index];
    final Task? edited = await TaskEditorDialog.show(context, initial: original);
    if (edited == null) return;
    setState(() {
      _tasks.removeAt(index);
      _insertTask(edited);
    });
  }

  void _deleteTask(int index) {
    setState(() => _tasks.removeAt(index));
  }

  void _finish(RoutineEditorOutcome outcome) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Give this routine a name first.');
      return;
    }
    if (_tasks.isEmpty) {
      _snack('Add at least one task to the routine.');
      return;
    }
    Navigator.of(context).pop(
      RoutineEditorResult(
        outcome: outcome,
        name: name,
        tasks: _tasks,
        routineId: widget.existingRoutineId,
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _insertTask(Task task) {
    final newTask = _cloneTask(task);
    final newKey = _taskTimeKey(newTask);
    int insertIndex = _tasks.length;
    for (int i = 0; i < _tasks.length; i++) {
      if (newKey < _taskTimeKey(_tasks[i])) {
        insertIndex = i;
        break;
      }
    }
    _tasks.insert(insertIndex, newTask);
  }

  int _taskTimeKey(Task task) {
    final minutes = _timeToMinutes(task.startTime, task.period);
    if (minutes != null) return minutes;
    final endMinutes = _timeToMinutes(task.endTime, task.period);
    if (endMinutes != null) return endMinutes + 1;
    final idx = _tasks.indexOf(task);
    final fallbackBase = 24 * 60 * 2;
    if (idx >= 0) return fallbackBase + idx;
    return fallbackBase + _tasks.length;
  }

  int? _timeToMinutes(String? time, String? period) {
    if (time == null || time.trim().isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    int hour24 = hour % 12;
    final periodNorm = (period ?? '').trim().toUpperCase();
    if (periodNorm == 'PM') hour24 += 12;
    if (periodNorm != 'PM' && periodNorm != 'AM' && hour == 12) {
      hour24 = 0;
    }
    return hour24 * 60 + minute;
  }
}

class _RoutineTaskCard extends StatelessWidget {
  const _RoutineTaskCard({
    super.key,
    required this.task,
    this.onEdit,
    this.onDelete,
  });

  final Task task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasSteps = task.steps.any((s) => s.trim().isNotEmpty);
    return Card(
      child: ExpansionTile(
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_formatTime(task)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                tooltip: 'Edit task',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete task',
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
          ],
        ),
        children: hasSteps
            ? task.steps
                .where((s) => s.trim().isNotEmpty)
                .map(
                  (s) => Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('• ${s.trim()}'),
                    ),
                  ),
                )
                .toList()
            : [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No steps added'),
                ),
              ],
      ),
    );
  }

  String _formatTime(Task t) {
    final start = t.startTime?.trim();
    final end = t.endTime?.trim();
    final period = (t.period ?? '').trim().toUpperCase();
    if ((start == null || start.isEmpty) && (end == null || end.isEmpty)) {
      return 'No default time';
    }
    final buffer = StringBuffer();
    if (start != null && start.isNotEmpty) buffer.write(start);
    if (end != null && end.isNotEmpty) buffer.write(' – $end');
    if (period.isNotEmpty) buffer.write(' $period');
    return buffer.toString();
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
  );
}
