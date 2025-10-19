import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({super.key, this.initial});
  final Task? initial;

  static Future<Task?> show(BuildContext context, {Task? initial}) {
    return showDialog<Task>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskEditorDialog(initial: initial),
    );
  }

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  String _period = 'AM';
  List<String> _steps = [''];
  int _currentStep = 0;
  final _stepCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _startCtrl = TextEditingController(text: t?.startTime ?? '');
    _endCtrl   = TextEditingController(text: t?.endTime ?? '');
    _period    = t?.period ?? 'AM';
    _steps     = t?.steps.isNotEmpty == true ? List.of(t!.steps) : [''];
    _stepCtrl.text = _steps[_currentStep];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _stepCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final task = Task(
      title: title,
      steps: _steps.where((s) => s.trim().isNotEmpty).toList(),
      startTime: _startCtrl.text.trim().isEmpty ? null : _startCtrl.text.trim(),
      endTime: _endCtrl.text.trim().isEmpty ? null : _endCtrl.text.trim(),
      period: _period,
      completed: widget.initial?.completed ?? false,
      hidden: widget.initial?.hidden ?? false,
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Task' : 'Edit Task'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _startCtrl, decoration: const InputDecoration(labelText: 'Start (e.g., 1:30)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _endCtrl, decoration: const InputDecoration(labelText: 'End (e.g., 2:00)'))),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _period,
                  items: const [
                    DropdownMenuItem(value: 'AM', child: Text('AM')),
                    DropdownMenuItem(value: 'PM', child: Text('PM')),
                  ],
                  onChanged: (v) => setState(() => _period = v ?? 'AM'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _stepCtrl, decoration: const InputDecoration(labelText: 'Step'))),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add step',
                  onPressed: () {
                    setState(() {
                      _steps[_currentStep] = _stepCtrl.text;
                      _steps.add('');
                      _currentStep = _steps.length - 1;
                      _stepCtrl.text = _steps[_currentStep];
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}