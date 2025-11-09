import 'package:flutter/material.dart';

import '../data/premade_routines.dart';
import '../models/routine_template.dart';
import '../pages/routine_editor_page.dart';
import '../services/routine_service.dart';

class RoutinePickerDialog extends StatefulWidget {
  const RoutinePickerDialog({super.key});

  static Future<RoutineEditorResult?> pick(BuildContext context) {
    return showDialog<RoutineEditorResult?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const RoutinePickerDialog(),
    );
  }

  @override
  State<RoutinePickerDialog> createState() => _RoutinePickerDialogState();
}

class _RoutinePickerDialogState extends State<RoutinePickerDialog> {
  String _query = '';
  bool _loadingSaved = true;
  String? _error;
  List<RoutineTemplate> _saved = const [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    setState(() {
      _loadingSaved = true;
      _error = null;
    });
    try {
      final routines = await RoutineService.fetchRoutines();
      if (!mounted) return;
      setState(() {
        _saved = routines;
        _loadingSaved = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingSaved = false;
      });
    }
  }

  List<_RoutineItem> get _filteredRoutines {
    final q = _query.trim().toLowerCase();
    final items = [
      ..._saved.map((r) => _RoutineItem(template: r, isSaved: true)),
      ...kPremadeRoutines.map((r) => _RoutineItem(template: r, isSaved: false)),
    ];
    if (q.isEmpty) return items;
    return items.where((item) {
      final haystack = (item.template.title + ' ' + item.template.description).toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final routines = _filteredRoutines;
    return AlertDialog(
      title: const Text('Premade routines'),
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
                      hintText: 'Search routines…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                IconButton(
                  tooltip: 'Create routine',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _createRoutine(context),
                ),
                IconButton(
                  tooltip: 'Delete all my routines',
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: _saved.isEmpty || _loadingSaved ? null : _deleteAllRoutines,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
              ),
            SizedBox(
              height: 360,
              child: _loadingSaved
                  ? const Center(child: CircularProgressIndicator())
                  : routines.isEmpty
                      ? const Center(child: Text('No routines match your search.'))
                      : Material(
                          color: Colors.transparent,
                          child: ListView.separated(
                            itemCount: routines.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = routines[index];
                              return ListTile(
                                leading: Icon(item.isSaved ? Icons.star_outline : Icons.auto_awesome),
                                title: Text(item.template.title),
                                subtitle: Text(
                                  _buildSubtitle(item.template),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Deploy routine',
                                      icon: const Icon(Icons.rocket_launch_outlined),
                                      onPressed: () => _deployRoutine(item),
                                    ),
                                    Text(item.isSaved ? 'Mine' : 'Built-in',
                                        style: Theme.of(context).textTheme.labelSmall),
                                    if (item.isSaved)
                                      IconButton(
                                        tooltip: 'Delete routine',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteRoutine(item.template),
                                      ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => _openRoutine(item),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _buildSubtitle(RoutineTemplate routine) {
    final desc = routine.description.trim().isEmpty ? 'No description' : routine.description.trim();
    final tasks = routine.tasks.length;
    return '$desc · $tasks task${tasks == 1 ? '' : 's'}';
  }

  Future<void> _openRoutine(_RoutineItem item) async {
    final result = await RoutineEditorPage.open(
      context,
      tasks: item.template.cloneTasks(),
      initialName: item.template.title,
      title: item.template.title,
      showDeployButton: false,
      existingRoutineId: item.isSaved ? item.template.id : null,
    );
    if (result == null || !mounted) return;
    if (result.outcome == RoutineEditorOutcome.deploy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deploy routines from the AI generator.')),
      );
      return;
    }
    if (result.outcome == RoutineEditorOutcome.saveRoutine) {
      await _saveRoutineResult(result, existingId: item.isSaved ? item.template.id : null);
    }
  }

  Future<void> _createRoutine(BuildContext dialogContext) async {
    final result = await RoutineEditorPage.open(
      dialogContext,
      tasks: const [],
      initialName: 'New Routine',
      showDeployButton: false,
    );
    if (result == null || !mounted) return;
    if (result.outcome == RoutineEditorOutcome.deploy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deploy routines from the AI generator.')),
      );
      return;
    }
    if (result.outcome == RoutineEditorOutcome.saveRoutine) {
      await _saveRoutineResult(result);
    }
  }

  Future<void> _saveRoutineResult(RoutineEditorResult result, {String? existingId}) async {
    try {
      await RoutineService.saveRoutine(
        routineId: existingId ?? result.routineId,
        title: result.name,
        tasks: result.tasks,
      );
      if (!mounted) return;
      await _loadSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved routine "${result.name}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save routine: $e')),
      );
    }
  }

  Future<void> _deleteRoutine(RoutineTemplate template) async {
    try {
      await RoutineService.deleteRoutine(template.id);
      if (!mounted) return;
      await _loadSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${template.title}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete routine: $e')),
      );
    }
  }

  Future<void> _deleteAllRoutines() async {
    if (_saved.isEmpty) {
      _snack('No saved routines to delete.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all routines?'),
        content: Text('Remove ${_saved.length} saved routine${_saved.length == 1 ? '' : 's'} permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete all')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (final routine in _saved) {
        await RoutineService.deleteRoutine(routine.id);
      }
      if (!mounted) return;
      await _loadSaved();
      _snack('Deleted all saved routines.');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete routines: $e');
    }
  }

  void _deployRoutine(_RoutineItem item) {
    Navigator.of(context).pop(
      RoutineEditorResult(
        outcome: RoutineEditorOutcome.deploy,
        name: item.template.title,
        tasks: item.template.cloneTasks(),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoutineItem {
  const _RoutineItem({required this.template, required this.isSaved});
  final RoutineTemplate template;
  final bool isSaved;
}
