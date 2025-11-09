// lib/pages/homepage.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/config/backend_config.dart';
import 'package:my_app/data/globals.dart';
import 'package:my_app/utils/task_step_resolver.dart';
import '../task_controller.dart';
import '../models/task.dart';
import '../services/family_service.dart';

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
  static const _base = BackendConfig.baseUrl;
  String? _selectedChild;
  List<FamilyMember> _children = const <FamilyMember>[];
  bool _childrenLoading = false;
  String? _childrenError;
  int _pendingLeaveRequests = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController();
    _loadFromServer();
    _loadChildren();
  }

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  Future<void> _loadFromServer() async {
    try {
      final uri = _buildProfileUri();
      final res = await http.get(uri, headers: _jsonHeaders);
      if (res.statusCode != 200) {
        _toast('Failed to load profile: ${res.statusCode}');
        return;
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final blocks = (body['schedule_blocks'] as List? ?? const []);
      final tasks = <Task>[];
      for (final b in blocks) {
        final m = (b as Map).cast<String, dynamic>();
        tasks.add(
          Task(
            title: (m['title'] ?? '').toString(),
            startTime: (m['startTime'] ?? '').toString().isEmpty ? null : (m['startTime'] as String),
            endTime: (m['endTime'] ?? '').toString().isEmpty ? null : (m['endTime'] as String),
            period: (m['period'] ?? '').toString().isEmpty ? null : (m['period'] as String),
            steps: (m['steps'] is List) ? List<String>.from(m['steps'] as List) : const <String>[],
            hidden: (m['hidden'] is bool) ? m['hidden'] as bool : false,
            completed: (m['completed'] is bool) ? m['completed'] as bool : false,
            familyTag: ((m['family_tag'] ?? '').toString().isEmpty ? null : m['family_tag'].toString()),
          ),
        );
      }
      _ctrl.replaceAll(tasks);
    } catch (e) {
      _toast('Load error: $e');
    }
  }

  Uri _buildProfileUri() {
    final target = _selectedChild;
    if (target == null || target.isEmpty) {
      return Uri.parse('$_base/profile');
    }
    final encoded = Uri.encodeComponent(target);
    return Uri.parse('$_base/profile?target_child=$encoded');
  }

  Map<String, dynamic> _taskToBlock(Task t) => <String, dynamic>{
        'title': t.title,
        'startTime': t.startTime,
        'endTime': t.endTime,
        'period': t.period,
        'steps': t.steps,
        'hidden': t.hidden,
        'completed': t.completed,
        'family_tag': t.familyTag,
      };

  Future<bool> _serverAdd(Task t) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/add'),
        headers: _jsonHeaders,
        body: json.encode(
          _withTarget(
            {'block': _taskToBlock(t)},
            forFamily: _isFamilyMode,
          ),
        ),
      );
      if (res.statusCode == 200 && _isFamilyMode) {
        try {
          final data = json.decode(res.body);
          if (data is Map && data['family_tag'] is String) {
            final tag = data['family_tag'].toString().trim();
            t.familyTag = tag.isEmpty ? null : tag;
          }
        } catch (_) {}
        return true;
      } else if (res.statusCode == 200) {
        return true;
      } else {
        _toast('Server add failed (${res.statusCode})');
      }
    } catch (e) {
      _toast('Add error: $e');
    }
    return false;
  }

  Future<void> _serverEdit(Task oldT, Task newT) async {
    final forFamily = _isFamilyMode && (oldT.familyTag?.isNotEmpty ?? false);
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/edit'),
        headers: _jsonHeaders,
        body: json.encode(
          _withTarget(
            {
              'old_block': _taskToBlock(oldT),
              'new_block': _taskToBlock(newT),
            },
            forFamily: forFamily,
            familyTag: oldT.familyTag,
          ),
        ),
      );
      if (res.statusCode != 200) _toast('Server edit failed (${res.statusCode})');
    } catch (e) {
      _toast('Edit error: $e');
    }
  }

  Future<void> _serverRemove(Task t) async {
    final forFamily = _isFamilyMode && (t.familyTag?.isNotEmpty ?? false);
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/delete'),
        headers: _jsonHeaders,
        body: json.encode(
          _withTarget(
            {'block': _taskToBlock(t)},
            forFamily: forFamily,
            familyTag: t.familyTag,
          ),
        ),
      );
      if (res.statusCode == 404) {
        _toast('Task already removed on server. Refreshing…');
        await _loadFromServer();
        return;
      }
      if (res.statusCode != 200) {
        _toast('Server delete failed (${res.statusCode})');
      }
    } catch (e) {
      _toast('Delete error: $e');
    }
  }

  Future<void> _loadChildren() async {
    setState(() {
      _childrenLoading = true;
      _childrenError = null;
    });
    try {
      final members = await FamilyService.fetchMembers();
      if (!mounted) return;
      final children = members?.children ?? const [];
      final missingSelection = _selectedChild != null && children.every((c) => c.username != _selectedChild);
      setState(() {
        _children = children;
        _childrenLoading = false;
        _pendingLeaveRequests =
            (members != null && members.isMaster) ? members.pendingRequests : 0;
        _childrenError = (members == null && _selectedChild != null)
            ? 'Unable to load family info.'
            : null;
        if (missingSelection || children.isEmpty) _selectedChild = null;
      });
      if (missingSelection) _loadFromServer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _childrenLoading = false;
        _childrenError = (_children.isNotEmpty)
            ? 'Unable to load family info.'
            : null;
        _pendingLeaveRequests = 0;
      });
    }
  }

  Future<void> _changeAssignee(String? child) async {
    if (_selectedChild == child) return;
    setState(() => _selectedChild = child);
    await _loadFromServer();
  }

  Map<String, dynamic> _withTarget(
    Map<String, dynamic> payload, {
    bool forFamily = false,
    String? familyTag,
  }) {
    final map = Map<String, dynamic>.from(payload);
    final tagInPayload = (familyTag ?? _extractFamilyTag(map))?.trim();
    final shouldApplyToFamily = forFamily || (tagInPayload != null && tagInPayload.isNotEmpty);
    if (shouldApplyToFamily) {
      map['apply_to_family'] = true;
      if (tagInPayload != null && tagInPayload.isNotEmpty) {
        map['family_tag'] = tagInPayload;
      }
    } else if (_selectedChild != null && _selectedChild!.isNotEmpty) {
      map['target_child'] = _selectedChild;
    }
    return map;
  }

  String? _extractFamilyTag(Map<String, dynamic> payload) {
    for (final value in payload.values) {
      if (value is Map && value['family_tag'] is String) {
        final tag = value['family_tag'].toString().trim();
        if (tag.isNotEmpty) return tag;
      }
    }
    return null;
  }

  String get _assigneeLabel {
    if (_selectedChild != null && _selectedChild!.isNotEmpty) {
      return _childLabel(_selectedChild!);
    }
    if (_children.isEmpty) return 'Family schedule';
    return 'Family schedule (all children)';
  }

  String _childLabel(String username) {
    for (final child in _children) {
      if (child.username == username) {
        return child.displayName;
      }
    }
    return username;
  }

  Future<void> _handleMenuSelect(String value) async {
    switch (value) {
      case 'profile':
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        if (!mounted) return;
        _loadChildren();
        _loadFromServer();
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
      final ok = await _serverAdd(task);
      if (!ok) await _loadFromServer();
      _snack('Task added');
    }
  }

  Future<void> _addFromTemplate() async {
    final Task? templated = await TemplatePickerDialog.pickAndEdit(context);
    if (templated != null && mounted) {
      setState(() => _ctrl.add(templated));
      final ok = await _serverAdd(templated);
      if (!ok) await _loadFromServer();
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
        await _serverAdd(t);
      }
      await _loadFromServer();
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
            child: IconButton(
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _canAssign ? () => _askAi() : null,
            ),
          ),
          Tooltip(
            message: 'Choose a premade task',
            child: IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _canAssign ? () => _addFromTemplate() : null,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) {
              _handleMenuSelect(value);
            },
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
      body: Column(
        children: [
          if (_pendingLeaveRequests > 0) _leaveRequestsBanner(),
          _assignmentBanner(),
          Expanded(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => _ParentTasksSectionWithSync(
                ctrl: _ctrl,
                onEdited: _onEdit,
                onDeleted: _onDelete,
                familyMode: _isFamilyMode,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _canAssign ? () => _addTask() : null,
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

  Widget _assignmentBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You're currently assigning tasks to $_assigneeLabel",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_childrenLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_children.isEmpty)
            const Text('No children linked to this family yet.')
          else
            DropdownButton<String?>(
              value: _selectedChild,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Family schedule (all children)')),
                ..._children.map(
                  (child) => DropdownMenuItem<String?>(
                    value: child.username,
                    child: Text(child.displayName),
                  ),
                ),
              ],
              onChanged: _childrenLoading
                  ? null
                  : (value) {
                      _changeAssignee(value);
                    },
            ),
          if (_isFamilyMode && _children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Family schedule will create or remove this task for every child.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_childrenError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _childrenError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            )
        ],
      ),
    );
  }

  Widget _leaveRequestsBanner() {
    final count = _pendingLeaveRequests;
    final text = count == 1
        ? '1 child has requested to leave the family.'
        : '$count children have requested to leave the family.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.8),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => _handleMenuSelect('profile'),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  bool get _isFamilyMode => _children.isNotEmpty && (_selectedChild == null || _selectedChild!.isEmpty);
  bool get _canAssign => true;
}

class _ParentTasksSectionWithSync extends StatelessWidget {
  const _ParentTasksSectionWithSync({
    required this.ctrl,
    required this.onEdited,
    required this.onDeleted,
    required this.familyMode,
  });

  final TaskController ctrl;
  final Future<void> Function(Task before, Task after) onEdited;
  final Future<void> Function(Task t) onDeleted;
  final bool familyMode;

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
        final isFamilyTask = (t.familyTag?.isNotEmpty ?? false);
        final canMutate = !familyMode || isFamilyTask;
        return TaskTile(
          task: t,
          strikeThroughWhenCompleted: strikeThroughWhenCompleted,
          onToggle: familyMode ? () {} : () => _handleToggle(t),
          onEdit: canMutate ? () => _handleEdit(context, t) : null,
          onDelete: canMutate ? () => _handleDelete(t) : null,
          onOpen: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskDetailPage(
                  task: t,
                  stepsWithImages: resolveTaskSteps(t),
                ),
              ),
            );
          },
        );
      }),
    ];
  }

  void _handleToggle(Task t) {
    final idx = ctrl.all.indexOf(t);
    if (idx == -1) return;
    final before = _cloneTask(ctrl.all[idx]);
    ctrl.toggleCompleted(idx);
    onEdited(before, ctrl.all[idx]);
  }

  Future<void> _handleEdit(BuildContext context, Task t) async {
    final idx = ctrl.all.indexOf(t);
    if (idx == -1) return;
    final before = ctrl.all[idx];
    final edited = await TaskEditorDialog.show(context, initial: t);
    if (edited != null) {
      ctrl.update(idx, edited);
      onEdited(before, edited);
    }
  }

  void _handleDelete(Task t) {
    final idx = ctrl.all.indexOf(t);
    if (idx == -1) return;
    final toRemove = ctrl.all[idx];
    ctrl.removeAt(idx);
    onDeleted(toRemove);
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
      familyTag: t.familyTag,
    );
