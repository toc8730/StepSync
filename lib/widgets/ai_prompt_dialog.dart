import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/ai_task_generator.dart';
import 'task_editor_dialog.dart';

class AiPromptDialog extends StatefulWidget {
  const AiPromptDialog({super.key});

  static Future<List<Task>> showAndGenerate(BuildContext context) async {
    final res = await showDialog<List<Task>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const AiPromptDialog(),
    );
    return res ?? <Task>[];
  }

  @override
  State<AiPromptDialog> createState() => _AiPromptDialogState();
}

class _AiPromptDialogState extends State<AiPromptDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ask AI to make tasks'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'e.g., Morning routine for school days with 30-min homework block',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : () async {
            setState(() { _busy = true; _err = null; });
            try {
              final generated = await AiTaskGenerator.fromPrompt(_ctrl.text);
              // Let user tweak each generated task in your existing editor
              final accepted = <Task>[];
              for (final t in generated) {
                final edited = await TaskEditorDialog.show(context, initial: t);
                if (edited != null) accepted.add(edited);
              }
              if (!mounted) return;
              Navigator.pop(context, accepted);
            } catch (e) {
              setState(() { _err = 'Failed to generate: $e'; _busy = false; });
            }
          },
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Generate'),
        ),
      ],
    );
  }
}