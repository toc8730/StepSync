// lib/pages/homepage.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/data/globals.dart';
import '../task_controller.dart';
import '../models/task.dart';

import '../widgets/task_editor_dialog.dart';
import '../widgets/template_picker_dialog.dart';
import '../widgets/ai_prompt_dialog.dart';
import '../widgets/task_tile.dart';
import '../pages/task_detail_page.dart';
import 'login_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  final String username;
  final String token;
  const HomePage({super.key, required this.username, required this.token});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TaskController _ctrl;
  static const _base = 'http://127.0.0.1:5000';

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController();
    _loadFromServer();
  }

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  Future<void> _loadFromServer() async {
    try {
      final res = await http.get(Uri.parse('$_base/profile'), headers: _jsonHeaders);
      if (res.statusCode != 200) {
        _toast('Failed to load profile: ${res.statusCode}');
        return;
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final blocks = (body['schedule_blocks'] as List? ?? const []);
      for (final b in blocks) {
        final m = (b as Map).cast<String, dynamic>();
        _ctrl.load(
          Task(
            title: (m['title'] ?? '').toString(),
            startTime: (m['startTime'] ?? '').toString().isEmpty ? null : (m['startTime'] as String),
            endTime: (m['endTime'] ?? '').toString().isEmpty ? null : (m['endTime'] as String),
            period: (m['period'] ?? '').toString().isEmpty ? null : (m['period'] as String),
            steps: (m['steps'] is List) ? List<String>.from(m['steps'] as List) : const <String>[],
            hidden: (m['hidden'] is bool) ? m['hidden'] as bool : false,
            completed: (m['completed'] is bool) ? m['completed'] as bool : false,
          ),
        );
      }
      setState(() {});
    } catch (e) {
      _toast('Load error: $e');
    }
  }

  Map<String, dynamic> _taskToBlock(Task t) => <String, dynamic>{
        'title': t.title,
        'startTime': t.startTime,
        'endTime': t.endTime,
        'period': t.period,
        'steps': t.steps,
        'hidden': t.hidden,
        'completed': t.completed,
      };

  Future<void> _serverAdd(Task t) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/add'),
        headers: _jsonHeaders,
        body: json.encode({'block': _taskToBlock(t)}),
      );
      if (res.statusCode != 200) _toast('Server add failed (${res.statusCode})');
    } catch (e) {
      _toast('Add error: $e');
    }
  }

  Future<void> _serverEdit(Task oldT, Task newT) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/edit'),
        headers: _jsonHeaders,
        body: json.encode({
          'old_block': _taskToBlock(oldT),
          'new_block': _taskToBlock(newT),
        }),
      );
      if (res.statusCode != 200) _toast('Server edit failed (${res.statusCode})');
    } catch (e) {
      _toast('Edit error: $e');
    }
  }

  Future<void> _serverRemove(Task t) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/delete'),
        headers: _jsonHeaders,
        body: json.encode({'block': _taskToBlock(t)}),
      );
      if (res.statusCode != 200) _toast('Server delete failed (${res.statusCode})');
    } catch (e) {
      _toast('Delete error: $e');
    }
  }

  Future<void> _handleMenuSelect(String value) async {
    switch (value) {
      case 'profile':
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        break;
      case 'signout':
        if (!mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
        break;
    }
  }

  Future<void> _addTask() async {
    final Task? task = await TaskEditorDialog.show(context);
    if (task != null && mounted) {
      setState(() => _ctrl.add(task));
      _serverAdd(task);
      _snack('Task added');
    }
  }

  Future<void> _addFromTemplate() async {
    final Task? templated = await TemplatePickerDialog.pickAndEdit(context);
    if (templated != null && mounted) {
      setState(() => _ctrl.add(templated));
      _serverAdd(templated);
      _snack('Template added');
    }
  }

  Future<void> _askAi() async {
    final tasks = await AiPromptDialog.showAndGenerate(context);
    if (tasks.isNotEmpty && mounted) {
      setState(() {
        for (final t in tasks) {
          _ctrl.add(t);
        }
      });
      for (final t in tasks) {
        _serverAdd(t);
      }
      _snack('${tasks.length} task${tasks.length == 1 ? '' : 's'} added from AI');
    }
  }

  Future<void> _onEdit(Task before, Task after) async => _serverEdit(before, after);
  Future<void> _onDelete(Task t) async => _serverRemove(t);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          Tooltip(
            message: 'Ask AI to generate tasks',
            child: IconButton(icon: const Icon(Icons.auto_fix_high), onPressed: _askAi),
          ),
          Tooltip(
            message: 'Choose a premade task',
            child: IconButton(icon: const Icon(Icons.auto_awesome), onPressed: _addFromTemplate),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: _handleMenuSelect,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => _ParentTasksSectionWithSync(
          ctrl: _ctrl,
          onEdited: _onEdit,
          onDeleted: _onDelete,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }
}

class _ParentTasksSectionWithSync extends StatelessWidget {
  const _ParentTasksSectionWithSync({
    required this.ctrl,
    required this.onEdited,
    required this.onDeleted,
  });

  final TaskController ctrl;
  final Future<void> Function(Task before, Task after) onEdited;
  final Future<void> Function(Task t) onDeleted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _header(context, 'Earlier Today', 'Before now', ctrl.earlierToday.length, Icons.wb_sunny_outlined),
        ..._buildList(context, ctrl.earlierToday, strikeThroughWhenCompleted: true),
        const SizedBox(height: 12),
        _header(context, 'Later Today', 'After now', ctrl.laterToday.length, Icons.nights_stay_outlined),
        ..._buildList(context, ctrl.laterToday, strikeThroughWhenCompleted: true),
        const SizedBox(height: 12),
        _header(context, 'Completed Tasks', 'Done today', ctrl.completed.length, Icons.check_circle),
        ..._buildList(context, ctrl.completed, strikeThroughWhenCompleted: false),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _header(BuildContext c, String title, String subtitle, int count, IconData icon) {
    final color = Theme.of(c).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  subtitle,
                  style: Theme.of(c).textTheme.bodySmall?.copyWith(
                        color: Theme.of(c).colorScheme.onSurface.withOpacity(0.65),
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
            child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildList(BuildContext context, List items, {required bool strikeThroughWhenCompleted}) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No tasks here.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          ),
        )
      ];
    }
    return [
      const SizedBox(height: 8),
      ...List.generate(items.length, (i) {
        final t = items[i] as Task;
        return TaskTile(
          task: t,
          strikeThroughWhenCompleted: strikeThroughWhenCompleted,
          onToggle: () async {
            final idx = ctrl.all.indexOf(t);
            if (idx == -1) return;
            final before = _cloneTask(ctrl.all[idx]);
            ctrl.toggleCompleted(idx);
            await onEdited(before, ctrl.all[idx]);
          },
          onEdit: () async {
            final idx = ctrl.all.indexOf(t);
            if (idx == -1) return;
            final before = ctrl.all[idx];
            final edited = await TaskEditorDialog.show(context, initial: t);
            if (edited != null) {
              ctrl.update(idx, edited);
              await onEdited(before, edited);
            }
          },
          onDelete: () async {
            final idx = ctrl.all.indexOf(t);
            if (idx != -1) {
              final toRemove = ctrl.all[idx];
              ctrl.removeAt(idx);
              await onDeleted(toRemove);
            }
          },
          onOpen: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskDetailPage(
                  task: t,
                  stepsWithImages: const [], // images handled elsewhere
                ),
              ),
            );
          },
        );
      }),
    ];
  }
}

Task _cloneTask(Task t) => Task(
      title: t.title,
      steps: List<String>.from(t.steps),
      startTime: t.startTime,
      endTime: t.endTime,
      period: t.period,
      hidden: t.hidden,
      completed: t.completed,
    );
