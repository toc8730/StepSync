import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/task.dart';
import '../models/task_step.dart';
import '../widgets/media_picker.dart';

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

  @override
  void initState() {
    super.initState();
    _initTts();
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

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final steps = t.steps;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.title),
        actions: [
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopSpeaking,
              tooltip: 'Stop Reading',
            ),
        ],
      ),
      body: Row(
        children: [
          // LEFT COLUMN – steps
          Expanded(
            flex: 3,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: steps.length,
              itemBuilder: (context, i) {
                final text = steps[i].trim();
                if (text.isEmpty) return const SizedBox.shrink();

                final isActive = (_speakingIndex == i);
                return InkWell(
                  onTap: () => _speakStep(i, text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isActive
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                            : Theme.of(context).dividerColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isActive ? Icons.volume_up : Icons.volume_mute,
                          size: 18,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).iconTheme.color?.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // RIGHT COLUMN – images
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.stepsWithImages.isEmpty)
                    const Text(
                      'No images for this task.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ...widget.stepsWithImages.asMap().entries.map((entry) {
                      final i = entry.key;
                      final step = entry.value;
                      if (step.images.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Step ${i + 1}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 6),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: step.images.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            itemBuilder: (_, j) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                step.images[j].bytes,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
