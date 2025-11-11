// lib/widgets/task_editor_dialog.dart
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../data/images_repo.dart';

class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({super.key, this.initial, this.primaryButtonLabel = 'Save'});
  final Task? initial;
  final String primaryButtonLabel;

  static Future<Task?> show(BuildContext context, {Task? initial, String primaryButtonLabel = 'Save'}) {
    return showDialog<Task?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: TaskEditorDialog(initial: initial, primaryButtonLabel: primaryButtonLabel),
      ),
    );
  }

  // You already call this elsewhere from your templates helper.
  static Future<Task?> pickAndEdit(BuildContext context) {
    return show(context);
  }

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  // Task fields
  final _title = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  String _period = 'AM'; // AM / PM

  // Step model (dynamic count, arrow navigable)
  final List<TextEditingController> _stepsCtrls = [];
  final List<Uint8List?> _stepImages = [];
  int _index = 0; // current step index in the editor
  static const int _maxSteps = 12;

  String? _error; // form-level errors (e.g., invalid time)

  @override
  void initState() {
    super.initState();

    // Initialize from initial task (edit) or blank (create)
    if (widget.initial != null) {
      final t = widget.initial!;
      _title.text = t.title;
      if (t.startTime != null) _start.text = t.startTime!;
      if (t.endTime != null) _end.text = t.endTime!;
      final p = (t.period ?? '').trim().toUpperCase();
      if (p == 'AM' || p == 'PM') _period = p;

      // steps + images (one per step)
      final steps = t.steps.isEmpty ? <String>[''] : t.steps;
      final imgs = ImagesRepo.I.get(t, steps.length);
      for (int i = 0; i < steps.length; i++) {
        _stepsCtrls.add(TextEditingController(text: steps[i]));
        _stepImages.add(i < imgs.length ? imgs[i] : null);
        _stepsCtrls.last.addListener(_refreshButtonsState);
      }
    } else {
      // start with a single blank step
      _stepsCtrls.add(TextEditingController()..addListener(_refreshButtonsState));
      _stepImages.add(null);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    for (final c in _stepsCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- Time helpers ----------
  bool _validTime(String s) {
    // allows "1:00" or "01:00" through "12:59"
    final re = RegExp(r'^(?:0?[1-9]|1[0-2]):[0-5][0-9]$');
    return re.hasMatch(s.trim());
  }

  String _displayPreview() {
    final s = _start.text.trim();
    final e = _end.text.trim();
    final per = _period.toUpperCase();

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

    bool vs(String t) => _validTime(t);

    // If user entered something invalid, explicitly say so
    if (s.isNotEmpty && !vs(s)) return 'Invalid time';
    if (e.isNotEmpty && !vs(e)) return 'Invalid time';

    if (!vs(s) && !vs(e)) return '';
    if (vs(s) && !vs(e)) return '${fmt(s)} ${per.toLowerCase()}';
    if (!vs(s) && vs(e)) return '${fmt(e)} ${per.toLowerCase()}';

    // Cross-noon logic: if end < start in same period, flip end period
    final s24 = to24(s, per);
    final endSame24 = to24(e, per);
    final sameForward = endSame24 >= s24;
    final flipped = (per == 'AM') ? 'PM' : 'AM';
    final endFlip24 = to24(e, flipped);
    final flipForward = endFlip24 >= s24;
    final endPeriod = sameForward ? per : (flipForward ? flipped : per);

    return '${fmt(s)} ${per.toLowerCase()} – ${fmt(e)} ${endPeriod.toLowerCase()}';
  }

  // ---------- Step navigation & actions ----------
  bool get _isFirst => _index == 0;
  bool get _isLast => _index == _stepsCtrls.length - 1;

  void _refreshButtonsState() {
    // Just triggers a rebuild so Add button enablement updates as user types
    if (mounted) setState(() {});
  }

  Future<void> _goPrev() async {
    if (_isFirst) return;
    setState(() => _index--);
  }

  Future<void> _goNext() async {
    if (_isLast) return;
    setState(() => _index++);
  }

  bool get _canAddStepHere {
    // Don’t allow adding a new step if current step is empty
    return _stepsCtrls[_index].text.trim().isNotEmpty && _stepsCtrls.length < _maxSteps;
  }

  void _addStep() {
    if (!_canAddStepHere) {
      // No hover on many platforms, show a quick hint
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Step ${_index + 1} can’t be empty before adding a new one.'),
          duration: const Duration(milliseconds: 900),
        ),
      );
      return;
    }
    setState(() {
      _stepsCtrls.insert(_index + 1, TextEditingController()..addListener(_refreshButtonsState));
      _stepImages.insert(_index + 1, null);
      _index++; // jump to the newly created step
    });
  }

  void _attachOrChangeImage() async {
    const typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _stepImages[_index] = bytes;
    });
  }

  void _removeImage() {
    setState(() {
      _stepImages[_index] = null;
    });
  }

  // ---------- Save ----------
  void _save() {
    setState(() => _error = null);

    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }

    final s = _start.text.trim();
    final e = _end.text.trim();
    final hasS = s.isNotEmpty;
    final hasE = e.isNotEmpty;

    if (hasS && !_validTime(s)) {
      setState(() => _error = 'Start time is invalid. Use H:MM (e.g., 1:00).');
      return;
    }
    if (hasE && !_validTime(e)) {
      setState(() => _error = 'End time is invalid. Use H:MM (e.g., 1:00).');
      return;
    }

    // Collect only non-empty steps; images stay index-aligned
    final steps = <String>[];
    final images = <Uint8List?>[];
    for (int i = 0; i < _stepsCtrls.length; i++) {
      final txt = _stepsCtrls[i].text.trim();
      if (txt.isNotEmpty) {
        steps.add(txt);
        images.add(_stepImages[i]);
      }
    }

    // Must have at least one step? (You didn’t require it; leaving optional.)
    // Build Task
    final task = Task(
      title: title,
      startTime: hasS ? s : null,
      endTime: hasE ? e : null,
      period: (hasS || hasE) ? _period : null,
      steps: steps,
      completed: widget.initial?.completed ?? false,
      hidden: widget.initial?.hidden ?? false,
      familyTag: widget.initial?.familyTag,
    );

    // Store per-step images (in-memory)
    ImagesRepo.I.set(task, images.isEmpty ? List<Uint8List?>.filled(steps.length, null) : images);

    Navigator.of(context).pop<Task>(task);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _stepsCtrls.length;
    final preview = _displayPreview();
    final curText = _stepsCtrls[_index].text;
    final hasImg = _stepImages[_index] != null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'Create Task' : 'Edit Task',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Time row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _start,
                            decoration: const InputDecoration(
                              labelText: 'Start (H:MM)',
                              hintText: 'e.g., 8:00',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _end,
                            decoration: const InputDecoration(
                              labelText: 'End (H:MM)',
                              hintText: 'e.g., 8:10',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Will display: '),
                        Text(
                          preview.isEmpty ? '(no time)' : preview,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    // Step navigator header
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: _index == 0 ? 'First step' : 'Previous step',
                            onPressed: _isFirst ? null : _goPrev,
                            icon: const Icon(Icons.arrow_back_ios_new),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'Step ${_index + 1} of $total',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _isLast ? 'Last step' : 'Next step',
                            onPressed: _isLast ? null : _goNext,
                            icon: const Icon(Icons.arrow_forward_ios),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Image preview (one per step)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
                        child: hasImg
                            ? Image.memory(
                                _stepImages[_index]!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            : Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 56,
                                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Image actions
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _attachOrChangeImage,
                          icon: Icon(hasImg ? Icons.switch_camera : Icons.add_a_photo),
                          label: Text(hasImg ? 'Change image' : 'Attach image'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: hasImg ? _removeImage : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                        ),
                        const Spacer(),
                        Tooltip(
                          message: _canAddStepHere
                              ? 'Add a new step after this one'
                              : 'Step ${_index + 1} can’t be empty',
                          child: FilledButton.icon(
                            onPressed: _canAddStepHere ? _addStep : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Add step'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Step text field
                    TextField(
                      controller: _stepsCtrls[_index],
                      maxLines: null,
                      decoration: const InputDecoration(
                        labelText: 'Step text',
                        hintText: 'Describe what to do',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(widget.primaryButtonLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
