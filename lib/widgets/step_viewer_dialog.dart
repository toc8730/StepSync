import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/task.dart';
import '../models/task_step.dart';
import '../widgets/media_picker.dart';

/// Pop-out overlay: arrows to switch steps, TTS button + step text on top,
/// big image panel, arrows disabled at ends.
class StepViewerDialog extends StatefulWidget {
  const StepViewerDialog({
    super.key,
    required this.task,
    this.stepsWithImages = const <TaskStep>[],
    this.initialIndex = 0,
  });

  final Task task;
  final List<TaskStep> stepsWithImages; // index-aligned with task.steps
  final int initialIndex;

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

  int _clampIndex(int i) => i.clamp(0, _steps.length - 1);
  bool get _isFirst => _index <= 0;
  bool get _isLast => _index >= _steps.length - 1;

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
    final text = _steps[_index];
    if (text.isEmpty) return;
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    await _tts.stop();
    final res = await _tts.speak(text);
    if (res == 1) setState(() => _isSpeaking = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepText = _steps[_index];
    final total = _steps.length;

    final images = (_index < widget.stepsWithImages.length)
        ? widget.stepsWithImages[_index].images
        : const <PickedImage>[];

    final canSpeak = stepText.isNotEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title + close
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Step ${_index + 1} of $total',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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

            // Top strip: TTS + text
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message:
                        !canSpeak ? 'No text to read' : (_isSpeaking ? 'Stop reading' : 'Read this step'),
                    child: IconButton(
                      icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up),
                      onPressed: canSpeak ? _toggleSpeak : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stepText.isEmpty ? '(No text for this step)' : stepText,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Main: tall arrows + big image area
            Expanded(
              child: Row(
                children: [
                  _TallSideArrow(isLeft: true, enabled: !_isFirst, onTap: _goPrev),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _StepImageArea(images: images),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TallSideArrow(isLeft: false, enabled: !_isLast, onTap: _goNext),
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

class _TallSideArrow extends StatelessWidget {
  const _TallSideArrow({
    required this.isLeft,
    required this.enabled,
    required this.onTap,
  });

  final bool isLeft;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = isLeft ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios;
    return SizedBox(
      width: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: enabled
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                  : Theme.of(context).disabledColor.withOpacity(0.06),
              border: Border.all(
                color: enabled
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                    : Theme.of(context).disabledColor.withOpacity(0.15),
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 22,
                color: enabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor,
              ),
            ),
          ),
        ),
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