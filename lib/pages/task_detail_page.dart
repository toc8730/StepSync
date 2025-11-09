import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/task.dart';
import '../models/task_step.dart';

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({
    super.key,
    required this.task,
    this.stepsWithImages = const <TaskStep>[],
  });

  final Task task;
  final List<TaskStep> stepsWithImages;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  int? _speakingIndex;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  List<_StepDisplay> get _stepDisplays {
    final List<_StepDisplay> items = [];
    for (var i = 0; i < widget.task.steps.length; i++) {
      final text = widget.task.steps[i].trim();
      if (text.isEmpty) continue;
      final TaskStep? meta =
          i < widget.stepsWithImages.length ? widget.stepsWithImages[i] : null;
      final images = <Uint8List>[];
      if (meta != null) {
        for (final img in meta.images) {
          images.add(img.bytes);
        }
      }
      items.add(_StepDisplay(text: text, images: images));
    }
    return items;
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);

    try {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
      );

    } catch (_) {}

    _tts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _speakingIndex = null;
      });
    });
    _tts.setCancelHandler(() {
      setState(() {
        _isSpeaking = false;
        _speakingIndex = null;
      });
    });
  }

  Future<void> _speakStep(int index, String text) async {
    if (_isSpeaking && _speakingIndex == index) {
      await _stopSpeaking();
      return;
    }
    if (_isSpeaking) await _stopSpeaking();

    setState(() {
      _isSpeaking = true;
      _speakingIndex = index;
    });

    await _tts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _speakingIndex = null;
    });
  }

  void _goToStep(int delta) {
    final total = _stepDisplays.length;
    if (total == 0) return;
    if (_isSpeaking) {
      _stopSpeaking();
    }
    setState(() {
      final next = (_currentIndex + delta).clamp(0, total - 1);
      _currentIndex = next.toInt();
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _stepDisplays;
    final total = steps.length;
    final hasSteps = total > 0;
    final currentIndex = hasSteps
        ? (_currentIndex.clamp(0, total - 1) as num).toInt()
        : 0;
    final currentStep = hasSteps ? steps[currentIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopSpeaking,
              tooltip: 'Stop Reading',
            ),
        ],
      ),
      body: hasSteps
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Step ${currentIndex + 1} of $total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    currentStep!.text,
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton.filledTonal(
                                  tooltip: _isSpeaking && _speakingIndex == currentIndex
                                      ? 'Stop reading'
                                      : 'Read this step aloud',
                                  icon: Icon(
                                    _isSpeaking && _speakingIndex == currentIndex
                                        ? Icons.volume_up
                                        : Icons.volume_mute,
                                  ),
                                  onPressed: () => _speakStep(currentIndex, currentStep.text),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Expanded(child: _buildImageArea(currentStep.images)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: currentIndex > 0 ? () => _goToStep(-1) : null,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Previous'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: currentIndex < total - 1 ? () => _goToStep(1) : null,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Center(
              child: Text(
                'No steps provided for this task.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
              ),
            ),
    );
  }

  Widget _buildImageArea(List<Uint8List> images) {
    if (images.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('No image attached to this step'),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
      ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            images.first,
            fit: BoxFit.contain,
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          Text(
            'Showing 1 of ${images.length} images',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _StepDisplay {
  const _StepDisplay({required this.text, required this.images});
  final String text;
  final List<Uint8List> images;
}
