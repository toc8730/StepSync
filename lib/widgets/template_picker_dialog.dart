// lib/widgets/template_picker_dialog.dart
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/task_template.dart';
import '../data/premade_templates.dart';
import 'task_editor_dialog.dart';

/// A dialog that lists premade task templates.
/// When you tap one, it opens the TaskEditorDialog prefilled with the template.
/// Returns the final Task (or null if cancelled).
class TemplatePickerDialog extends StatefulWidget {
  const TemplatePickerDialog({super.key});

  /// Static helper to open, then immediately open the editor,
  /// and return the created/edited Task.
  static Future<Task?> pickAndEdit(BuildContext context) {
    return showDialog<Task?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const TemplatePickerDialog(),
    );
  }

  @override
  State<TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<TemplatePickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = kPremadeTemplates.where((t) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      final hay = [
        t.title.toLowerCase(),
        ...t.steps.map((s) => s.toLowerCase()),
      ].join(' ');
      return hay.contains(q);
    }).toList();

    return AlertDialog(
      title: const Text('Choose a template'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search templates…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Material(
                color: Colors.transparent,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final tmpl = filtered[index];
                    return ListTile(
                      title: Text(tmpl.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: _TemplateSubtitle(template: tmpl),
                      leading: const Icon(Icons.auto_awesome),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        // Convert to Task and open the editor prefilled.
                        final initialTask = tmpl.toTask();
                        final edited = await TaskEditorDialog.show(
                          context,
                          initial: initialTask,
                        );
                        if (!context.mounted) return;
                        // Close the picker and return the task to the caller.
                        Navigator.of(context).pop<Task?>(edited);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<Task?>(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TemplateSubtitle extends StatelessWidget {
  const _TemplateSubtitle({required this.template});
  final TaskTemplate template;

  @override
  Widget build(BuildContext context) {
    final hasTime = (template.start != null && template.start!.isNotEmpty) ||
        (template.end != null && template.end!.isNotEmpty);
    final p = (template.period ?? '').toLowerCase();
    final time =
        hasTime ? '${template.start ?? ''}${template.end != null ? ' – ${template.end}' : ''}'
                '${p.isNotEmpty ? ' $p' : ''}'
                : 'No default time';
    final stepsPreview = template.steps.isEmpty
        ? 'No steps'
        : template.steps.take(2).join(' • ') + (template.steps.length > 2 ? '…' : '');

    return Text('$time · $stepsPreview',
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}