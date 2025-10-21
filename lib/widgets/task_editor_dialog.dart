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
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  final TextEditingController _stepCtrl = TextEditingController();

  String _period = 'AM';
  List<String> _steps = [''];
  int _currentStep = 0;

  final RegExp _timeRe = RegExp(r'^(?:[1-9]|1[0-2]):[0-5][0-9]$');

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _startCtrl = TextEditingController(text: t?.startTime ?? '');
    _endCtrl   = TextEditingController(text: t?.endTime ?? '');
    _period    = t?.period ?? 'AM';
    _steps     = (t?.steps.isNotEmpty == true) ? List.of(t!.steps) : [''];
    _currentStep = 0;
    _stepCtrl.text = _steps[_currentStep];

    _stepCtrl.addListener(() => setState(() {}));
    _startCtrl.addListener(() => setState(() {}));
    _endCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _stepCtrl.dispose();
    super.dispose();
  }

  String? _timeValidator(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // optional
    if (!_timeRe.hasMatch(v)) return 'Use H:MM (1–12:00–59)';
    return null;
  }

  bool _isValidTime(String? v) => (v != null && v.trim().isNotEmpty && _timeRe.hasMatch(v.trim()));

  // Preview: flip AM/PM ONLY if interval crosses 12:00 (same logic as tile)
  String _displayTimePreview() {
    final start = _startCtrl.text.trim();
    final end   = _endCtrl.text.trim();
    final hasStart = start.isNotEmpty;
    final hasEnd   = end.isNotEmpty;

    if (!hasStart && !hasEnd) return '';

    final startOk = !hasStart || _isValidTime(start);
    final endOk   = !hasEnd   || _isValidTime(end);
    if (!startOk || !endOk) return 'Invalid time format. Use H:MM (1–12:00–59)';

    final period = _period.trim().toUpperCase();

    String fmt(String hhmm) {
      final parts = hhmm.split(':');
      final h = int.parse(parts[0]);
      final mm = parts[1].padLeft(2, '0');
      return (mm == '00') ? '$h' : '$h:$mm';
    }
    String lower(String p) => p.toLowerCase();

    int to24(String hhmm, String period) {
      final parts = hhmm.split(':');
      final h12 = int.parse(parts[0]) % 12;
      final mm = int.parse(parts[1]);
      final add = (period == 'PM') ? 12 : 0;
      return (h12 + add) * 60 + mm;
    }

    if (hasStart && !hasEnd) {
      return '${fmt(start)} ${lower(period)}';
    }
    if (!hasStart && hasEnd) {
      return '${fmt(end)} ${lower(period)}';
    }

    // both present
    final s24 = to24(start, period);

    final endSame24 = to24(end, period);
    final sameForward = endSame24 >= s24;

    final flipped = (period == 'AM') ? 'PM' : 'AM';
    final endFlip24 = to24(end, flipped);
    final flipForward = endFlip24 >= s24;

    final endPeriod = sameForward
        ? period
        : (flipForward ? flipped : period);

    final left  = '${fmt(start)} ${lower(period)}';
    final right = '${fmt(end)} ${lower(endPeriod)}';
    return '$left – $right';
  }

  // Steps logic unchanged
  bool get _currentStepEmpty => _stepCtrl.text.trim().isEmpty;

  void _goPrev() {
    if (_currentStep == 0) return;
    _steps[_currentStep] = _stepCtrl.text;
    setState(() {
      _currentStep--;
      _stepCtrl.text = _steps[_currentStep];
    });
  }

  void _goNext() {
    if (_currentStepEmpty) return;
    _steps[_currentStep] = _stepCtrl.text;
    if (_currentStep + 1 < _steps.length) {
      setState(() {
        _currentStep++;
        _stepCtrl.text = _steps[_currentStep];
      });
    } else {
      setState(() {
        _steps.add('');
        _currentStep++;
        _stepCtrl.text = '';
      });
    }
  }

  void _pruneEmptyStepsInPlace() {
    _steps = _steps.where((s) => s.trim().isNotEmpty).toList();
    if (_steps.isEmpty) {
      _steps = [''];
      _currentStep = 0;
      _stepCtrl.text = '';
      return;
    }
    if (_currentStep >= _steps.length) _currentStep = _steps.length - 1;
    _stepCtrl.text = _steps[_currentStep];
  }

  void _save() {
    _steps[_currentStep] = _stepCtrl.text;

    if (!_formKey.currentState!.validate()) return;

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    _pruneEmptyStepsInPlace();

    final task = Task(
      title: title,
      steps: _steps.where((s) => s.trim().isNotEmpty).toList(),
      startTime: _startCtrl.text.trim().isEmpty ? null : _startCtrl.text.trim(),
      endTime:   _endCtrl.text.trim().isEmpty   ? null : _endCtrl.text.trim(),
      period: _period,
      completed: widget.initial?.completed ?? false,
      hidden: widget.initial?.hidden ?? false,
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final stepCount = _steps.length;
    final isFirst = _currentStep == 0;
    final isLastExisting = _currentStep == stepCount - 1;
    final timePreview = _displayTimePreview();

    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Task' : 'Edit Task'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Start (e.g., 11:00)',
                        helperText: 'H:MM (1–12:00–59)',
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: _timeValidator,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _endCtrl,
                      decoration: const InputDecoration(
                        labelText: 'End (e.g., 12:15)',
                        helperText: 'H:MM (1–12:00–59)',
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: _timeValidator,
                    ),
                  ),
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

              const SizedBox(height: 8),
              if (timePreview.isNotEmpty)
                Text(timePreview, style: Theme.of(context).textTheme.bodyMedium),

              const SizedBox(height: 12),

              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous step',
                    onPressed: isFirst ? null : _goPrev,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Step ${_currentStep + 1} of $stepCount',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: _currentStepEmpty
                        ? 'Step ${_currentStep + 1} can’t be empty'
                        : (isLastExisting ? 'Move to new step' : 'Next step'),
                    child: IconButton(
                      onPressed: _currentStepEmpty ? null : _goNext,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _stepCtrl,
                decoration: const InputDecoration(labelText: 'Step text'),
                onChanged: (v) => _steps[_currentStep] = v,
                maxLines: null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}