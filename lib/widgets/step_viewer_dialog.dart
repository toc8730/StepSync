import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Pop-out viewer for a task's steps with left/right arrows and TTS.
/// - steps: List<String> of step texts (already trimmed)
/// - imageByStep: optional map {index -> path or URL}; if missing, shows a blank placeholder
Future<void> showStepViewerDialog(
  BuildContext context, {
  required String taskTitle,
  required List<String> steps,
  Map<int, String>? imageByStep,
  int initialIndex = 0,
}) {
  final Map<int, String> imgs = imageByStep ?? const {};
  int current = steps.isEmpty ? 0 : initialIndex.clamp(0, steps.length - 1);

  // Single TTS instance for this dialog
  final FlutterTts tts = FlutterTts();
  // Best-effort config (platform-safe; no awaits needed)
  tts.setLanguage('en-US');
  tts.setSpeechRate(0.45);
  tts.setVolume(1.0);
  tts.setPitch(1.0);

  Future<void> speak(String text) async {
    await tts.stop();
    if (text.trim().isEmpty) return;
    await tts.speak(text);
  }

  Future<void> stopTtsAndClose() async {
    await tts.stop();
    // ignore: use_build_context_synchronously
    Navigator.of(context).maybePop();
  }

  return showGeneralDialog(
    context: context,
    barrierLabel: 'Step viewer',
    barrierDismissible: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) {
      return StatefulBuilder(
        builder: (context, setState) {
          final bool atFirst = current <= 0;
          final bool atLast = steps.isEmpty || current >= steps.length - 1;
          final String stepText = steps.isEmpty
              ? 'No steps'
              : (steps[current].trim().isEmpty ? '(Untitled step)' : steps[current].trim());
          final String? imgPath = imgs[current];

          // Title includes the step text per request
          final String titleLine = 'Step ${steps.isEmpty ? 0 : (current + 1)}: $stepText';
          final String subtitleLine = 'of ${steps.length}';

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context).dividerColor.withOpacity(0.6),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Title (includes step text)
                                        Text(
                                          titleLine,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        // Small subtitle: total count
                                        Text(
                                          subtitleLine,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // TTS button (reads the title line / step text)
                                  Tooltip(
                                    message: 'Read title aloud',
                                    child: IconButton(
                                      icon: const Icon(Icons.volume_up_rounded),
                                      onPressed: stepText.trim().isEmpty ? null : () => speak(titleLine),
                                    ),
                                  ),
                                  // Close button
                                  IconButton(
                                    tooltip: 'Close',
                                    onPressed: stopTtsAndClose,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),

                            // Image area
                            Expanded(
                              child: Container(
                                alignment: Alignment.center,
                                color: Theme.of(context).colorScheme.surface,
                                child: _StepImage(path: imgPath),
                              ),
                            ),
                          ],
                        ),

                        // Left/right arrows
                        Positioned.fill(
                          child: Row(
                            children: [
                              _ArrowButton(
                                isLeft: true,
                                enabled: !atFirst,
                                onTap: () {
                                  if (!atFirst) {
                                    setState(() => current = current - 1);
                                    // optional: speak new title automatically on nav
                                    // speak('Step ${current + 1}: ${steps[current]}');
                                  }
                                },
                              ),
                              const Spacer(),
                              _ArrowButton(
                                isLeft: false,
                                enabled: !atLast,
                                onTap: () {
                                  if (!atLast) {
                                    setState(() => current = current + 1);
                                    // optional: speak new title automatically on nav
                                    // speak('Step ${current + 1}: ${steps[current]}');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() async {
    // Ensure TTS is stopped when dialog is dismissed by tapping outside
    await tts.stop();
  });
}

class _ArrowButton extends StatelessWidget {
  final bool isLeft;
  final bool enabled;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.isLeft,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.onSurface.withOpacity(0.85);
    final Color color = enabled ? base : base.withOpacity(0.25);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: IconButton.filledTonal(
        onPressed: enabled ? onTap : null,
        iconSize: 36,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(10),
        ),
        icon: Icon(
          isLeft ? Icons.arrow_back_ios_new_rounded : Icons.arrow_forward_ios_rounded,
          color: color,
        ),
      ),
    );
  }
}

class _StepImage extends StatelessWidget {
  final String? path;
  const _StepImage({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.trim().isEmpty) {
      return _placeholder(context);
    }

    // Network image
    if (path!.startsWith('http://') || path!.startsWith('https://')) {
      return Image.network(
        path!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }

    // Local file
    final file = File(path!);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }

    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
          ),
          const SizedBox(height: 10),
          Text(
            'No image for this step.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                ),
          ),
        ],
      ),
    );
  }
}