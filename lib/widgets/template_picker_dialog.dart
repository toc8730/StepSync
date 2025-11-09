// lib/widgets/template_picker_dialog.dart
import 'package:flutter/material.dart';

import '../data/premade_templates.dart';
import '../models/task.dart';
import '../models/task_template.dart';
import '../services/template_service.dart';
import 'task_editor_dialog.dart';

/// Dialog that lists premade task templates (built-in + user-created).
/// Selecting one opens [TaskEditorDialog] prefilled with the template and
/// returns the edited [Task] (or null if cancelled).
class TemplatePickerDialog extends StatefulWidget {
  const TemplatePickerDialog({super.key, this.canShareWithFamily = false});

  final bool canShareWithFamily;

  static Future<Task?> pickAndEdit(BuildContext context, {bool canShareWithFamily = false}) {
    return showDialog<Task?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => TemplatePickerDialog(canShareWithFamily: canShareWithFamily),
    );
  }

  @override
  State<TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<TemplatePickerDialog> {
  String _query = '';
  bool _loading = true;
  bool _mutating = false;
  String? _error;
  List<SavedTemplate> _personal = const <SavedTemplate>[];
  List<SavedTemplate> _family = const <SavedTemplate>[];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await TemplateService.fetchTemplates();
      if (!mounted) return;
      setState(() {
        _personal = result.personal;
        _family = result.family;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _handleCreateTemplate() async {
    final Task? base = await TaskEditorDialog.show(context);
    if (base == null) return;

    bool shareWithFamily = false;
    if (widget.canShareWithFamily) {
      final selection = await _promptShareScope();
      if (selection == null) return;
      shareWithFamily = selection;
    }

    setState(() => _mutating = true);
    try {
      final saved = await TemplateService.createTemplate(
        task: base,
        shareWithFamily: shareWithFamily,
      );
      if (!mounted) return;
      setState(() {
        if (saved.sharedWithFamily) {
          _family = [saved, ..._family];
        } else {
          _personal = [saved, ..._personal];
        }
      });
      _snack('Template saved.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _editTemplate(_TemplateListItem item) async {
    if (item.id == null) return;
    final Task? edited = await TaskEditorDialog.show(
      context,
      initial: item.template.toTask(),
    );
    if (edited == null) return;

    setState(() => _mutating = true);
    try {
      final updated = await TemplateService.updateTemplate(
        templateId: item.id!,
        task: edited,
      );
      if (!mounted) return;
      setState(() {
        if (item.source == _TemplateSource.personal) {
          _personal = _personal.map((t) => t.id == updated.id ? updated : t).toList();
        } else if (item.source == _TemplateSource.family) {
          _family = _family.map((t) => t.id == updated.id ? updated : t).toList();
        }
      });
      _snack('Template updated.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<bool?> _promptShareScope() async {
    bool share = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Share template'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    title: const Text('Only me'),
                    value: false,
                    groupValue: share,
                    onChanged: (value) => setStateDialog(() => share = value ?? false),
                  ),
                  RadioListTile<bool>(
                    title: const Text('All parents in my family'),
                    value: true,
                    groupValue: share,
                    onChanged: (value) => setStateDialog(() => share = value ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(share),
                  child: const Text('Save template'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  List<_TemplateListItem> get _items {
    final builtIn = kPremadeTemplates
        .map((tmpl) => _TemplateListItem(
              id: tmpl.id,
              template: tmpl,
              source: _TemplateSource.builtin,
              canEdit: false,
              canDelete: false,
            ))
        .toList();
    final personal = _personal
        .map((saved) => _TemplateListItem.fromSaved(saved, _TemplateSource.personal))
        .toList();
    final family = _family
        .map((saved) => _TemplateListItem.fromSaved(saved, _TemplateSource.family))
        .toList();
    return [...builtIn, ...personal, ...family];
  }

  List<_TemplateListItem> get _filteredItems {
    final query = _query.trim().toLowerCase();
    final items = _items;
    if (query.isEmpty) return items;
    return items.where((item) {
      final haystack = (item.template.title + ' ' + item.template.steps.join(' ')).toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _selectTemplate(TaskTemplate template) async {
    final initialTask = template.toTask();
    final edited = await TaskEditorDialog.show(
      context,
      initial: initialTask,
    );
    if (!mounted) return;
    Navigator.of(context).pop<Task?>(edited);
  }

  Future<void> _deleteTemplate(_TemplateListItem item) async {
    if (item.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('Remove "${item.template.title}" from your premade tasks?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _mutating = true);
    try {
      await TemplateService.deleteTemplate(item.id!);
      if (!mounted) return;
      setState(() {
        if (item.source == _TemplateSource.personal) {
          _personal = _personal.where((t) => t.id != item.id).toList();
        } else if (item.source == _TemplateSource.family) {
          _family = _family.where((t) => t.id != item.id).toList();
        }
      });
      _snack('Template deleted.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;

    return AlertDialog(
      title: const Text('Choose a template'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search templates…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh templates',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _loadTemplates,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create template'),
                onPressed: (_mutating || _loading) ? null : _handleCreateTemplate,
              ),
            ),
            if (_mutating) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No templates match your search.'))
                      : Material(
                          color: Colors.transparent,
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return ListTile(
                                enabled: !_mutating,
                                leading: Icon(item.icon),
                                title: Text(item.template.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  _templateSubtitle(item.template, item.source),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (item.source != _TemplateSource.builtin)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: Text(
                                          item.source == _TemplateSource.family ? 'Family' : 'Mine',
                                          style: Theme.of(context).textTheme.labelSmall,
                                        ),
                                      ),
                                    if (item.canEdit && item.id != null)
                                      IconButton(
                                        tooltip: 'Edit template',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: _mutating ? null : () => _editTemplate(item),
                                      ),
                                    if (item.canDelete && item.id != null)
                                      IconButton(
                                        tooltip: 'Delete template',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: _mutating ? null : () => _deleteTemplate(item),
                                      ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => _selectTemplate(item.template),
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

  String _templateSubtitle(TaskTemplate template, _TemplateSource source) {
    final hasTime = (template.start ?? '').isNotEmpty || (template.end ?? '').isNotEmpty;
    final period = (template.period ?? '').toUpperCase();
    final timeString = hasTime
        ? '${template.start ?? ''}'
            '${template.end != null ? ' – ${template.end}' : ''}'
            '${period.isNotEmpty ? ' $period' : ''}'
        : 'No default time';
    final stepsPreview = template.steps.isEmpty
        ? 'No steps'
        : template.steps.take(2).join(' • ') + (template.steps.length > 2 ? '…' : '');
    final prefix = source == _TemplateSource.builtin ? 'Built-in · ' : '';
    return '$prefix$timeString · $stepsPreview';
  }
}

enum _TemplateSource { builtin, personal, family }

class _TemplateListItem {
  _TemplateListItem({
    required this.id,
    required this.template,
    required this.source,
    required this.canEdit,
    required this.canDelete,
  });

  factory _TemplateListItem.fromSaved(SavedTemplate saved, _TemplateSource source) {
    return _TemplateListItem(
      id: saved.id,
      template: saved.template,
      source: source,
      canEdit: saved.canEdit,
      canDelete: saved.canDelete,
    );
  }

  final String? id;
  final TaskTemplate template;
  final _TemplateSource source;
  final bool canEdit;
  final bool canDelete;

  IconData get icon {
    switch (source) {
      case _TemplateSource.personal:
        return Icons.person_outline;
      case _TemplateSource.family:
        return Icons.groups;
      case _TemplateSource.builtin:
      default:
        return Icons.auto_awesome;
    }
  }
}
