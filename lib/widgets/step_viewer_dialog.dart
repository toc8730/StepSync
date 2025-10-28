import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/task.dart';
import '../models/task_step.dart';
import '../widgets/media_picker.dart';

/// Pop-out overlay to view a Task's steps one-by-one with left/right arrows.
/// - Shows "Step X of N"
/// - Disables left arrow on first step and right arrow on last step
/// - If there are images for the current step, shows them; otherwise a blank placeholder
/// - Text-to-speech button reads the current step text
class StepViewerDialog extends StatefulWidget {
  const StepViewerDialog({
    super.key,
    required this.task,
    this.stepsWithImages = const <TaskStep>[],
    this.initialIndex = 0,
  });

  final Task task;
  /// Must be index-aligned to task.steps (same length or shorter).
  final List<TaskStep> stepsWithImages;
  final int initialIndex;

  /// Call this to show the dialog.
  static Future<void> show(
    BuildContext context, {
    required Task task,
    List<TaskStep> stepsWithImages = const <TaskStep>[],
    int initialIndex = 0,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: StepViewerDialog(
          task: task,
          stepsWithImages: stepsWithImages,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<StepViewerDialog> createState() => _StepViewerDialogState();
}

class _StepViewerDialogState extends State<StepViewerDialog> {
  late final List<String> _steps;
  late int _index;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _steps = (widget.task.steps).map((e) => e.trim()).toList();
    if (_steps.isEmpty) _steps.add('');
    _index = _clampIndex(widget.initialIndex);
    final firstNonEmpty = _steps.indexWhere((s) => s.isNotEmpty);
    if (firstNonEmpty != -1) _index = firstNonEmpty;

    _initTts();
  }

  Future<void> _initTts() async {
    // Reasonable defaults; platform will pick a voice.
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      setState(() => _isSpeaking = true);
    });
    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
    _tts.setCancelHandler(() {
      setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((msg) {
      setState(() => _isSpeaking = false);
      // Optional: you could show a snackbar here if desired
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  int _clampIndex(int i) => i.clamp(0, _steps.length - 1);

  bool get _isFirst => _index <= 0;
  bool get _isLast => _index >= _steps.length - 1;

  void _goPrev() async {
    if (_isFirst) return;
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _index--;
    });
  }

  void _goNext() async {
    if (_isLast) return;
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _index++;
    });
  }

  Future<void> _toggleSpeak() async {
    final text = _steps[_index];
    if (text.isEmpty) return;

    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    // start speaking
    await _tts.stop(); // ensure clean start
    final res = await _tts.speak(text);
    if (res == 1) {
      setState(() => _isSpeaking = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepText = _steps[_index];
    final total = _steps.length;
    final images = (_index < widget.stepsWithImages.length)
        ? (widget.stepsWithImages[_index].images)
        : const <PickedImage>[];

    final canSpeak = stepText.isNotEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: Title + Close
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
                  // Left arrow
                  _SideArrow(
                    direction: AxisDirection.left,
                    onTap: _isFirst ? null : _goPrev,
                  ),

                  // Content area
                  Expanded(
                    child: Column(
                      children: [
                        // Image panel (or blank)
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _StepImageArea(images: images),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Step text with TTS button
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stepText.isEmpty ? '(No text for this step)' : stepText,
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

                  // Right arrow
                  _SideArrow(
                    direction: AxisDirection.right,
                    onTap: _isLast ? null : _goNext,
                  ),
                ],
              ),
            ),

            // Optional footer with the overall task title/time
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

class _StepImageArea extends StatelessWidget {
  const _StepImageArea({required this.images});
  final List<PickedImage> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      // Default blank area if no image uploaded
      return Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
        ),
      );
    }

    if (images.length == 1) {
      return Image.memory(
        images.first.bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    // If multiple images for the step, a simple PageView
    return PageView.builder(
      itemCount: images.length,
      itemBuilder: (_, i) => Image.memory(
        images[i].bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}