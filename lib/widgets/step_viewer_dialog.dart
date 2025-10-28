import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_selector/file_selector.dart';

import '../models/task.dart';
import '../data/images_repo.dart';

/// Pop-out overlay to view a Task's steps one-by-one with left/right arrows.
/// - "Step X of N", disabled arrows at ends
/// - Per-step image (one image max): attach/change or remove
/// - Text-to-speech for the step text
class StepViewerDialog extends StatefulWidget {
  const StepViewerDialog({
    super.key,
    required this.task,
    this.initialIndex = 0,
  });

  final Task task;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required Task task,
    int initialIndex = 0,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: StepViewerDialog(task: task, initialIndex: initialIndex),
      ),
    );
  }

  @override
  State<StepViewerDialog> createState() => _StepViewerDialogState();
}

class _StepViewerDialogState extends State<StepViewerDialog> {
  late final List<String> _steps;
  late int _index;

  // Per-step image bytes, kept in a small in-memory repo.
  late List<Uint8List?> _stepImages;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _steps = widget.task.steps.map((e) => e.trim()).toList();
    if (_steps.isEmpty) _steps.add('');
    _index = (widget.initialIndex).clamp(0, _steps.length - 1);

    // initialize images from repo
    _stepImages = ImagesRepo.I.get(widget.task, _steps.length);

    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _tts.setCancelHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  bool get _isFirst => _index == 0;
  bool get _isLast => _index == _steps.length - 1;
  String get _stepText => _steps[_index];

  Future<void> _goPrev() async {
    if (_isFirst) return;
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _index--;
    });
  }

  Future<void> _goNext() async {
    if (_isLast) return;
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _index++;
    });
  }

  Future<void> _toggleSpeak() async {
    if (_stepText.isEmpty) return;
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    await _tts.stop();
    final res = await _tts.speak(_stepText);
    if (res == 1) setState(() => _isSpeaking = true);
  }

  Future<void> _attachOrChangeImage() async {
    // Only one image per step: pick a single file
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
    ImagesRepo.I.setAt(widget.task, _index, bytes, _steps.length);
  }

  Future<void> _removeImage() async {
    setState(() {
      _stepImages[_index] = null;
    });
    ImagesRepo.I.setAt(widget.task, _index, null, _steps.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _steps.length;
    final bytes = _stepImages[_index];
    final canSpeak = _stepText.isNotEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: title + close
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Step ${_index + 1} of $total',
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

            // Main area: left arrow, content, right arrow
            Expanded(
              child: Row(
                children: [
                  _SideArrow(
                    direction: AxisDirection.left,
                    onTap: _isFirst ? null : _goPrev,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        // Image area (one image per step)
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: bytes == null
                                ? Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 64,
                                      color: theme.colorScheme.onSurface.withOpacity(0.35),
                                    ),
                                  )
                                : Image.memory(
                                    bytes,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Image actions
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _attachOrChangeImage,
                              icon: Icon(bytes == null ? Icons.add_a_photo : Icons.switch_camera),
                              label: Text(bytes == null ? 'Attach image' : 'Change image'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: bytes == null ? null : _removeImage,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove image'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Step text + TTS
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _stepText.isEmpty ? '(No text for this step)' : _stepText,
                                textAlign: TextAlign.left,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Tooltip(
                              message: !canSpeak
                                  ? 'No text to read'
                                  : (_isSpeaking ? 'Stop reading' : 'Read this step'),
                              child: IconButton(
                                onPressed: canSpeak ? _toggleSpeak : null,
                                icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _SideArrow(
                    direction: AxisDirection.right,
                    onTap: _isLast ? null : _goNext,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.task.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideArrow extends StatelessWidget {
  const _SideArrow({required this.direction, this.onTap});
  final AxisDirection direction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isLeft = direction == AxisDirection.left;
    final icon = isLeft ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios;
    final disabled = onTap == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: IconButton(
        icon: Icon(icon),
        disabledColor: Theme.of(context).disabledColor,
        onPressed: onTap,
        tooltip: disabled
            ? (isLeft ? 'First step' : 'Last step')
            : (isLeft ? 'Previous step' : 'Next step'),
      ),
    );
  }
}