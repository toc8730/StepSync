// lib/pages/child_home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/config/backend_config.dart';
import 'package:my_app/data/globals.dart';
import 'package:my_app/services/family_service.dart';
import 'package:my_app/utils/task_step_resolver.dart';
import '../task_controller.dart';
import '../models/task.dart';
import '../widgets/task_tile.dart';
import '../pages/task_detail_page.dart';
import 'login_page.dart';
import 'welcome_page.dart';
import 'profile_page.dart';

class ChildHomePage extends StatefulWidget {
  final String username;
  final String token;
  const ChildHomePage({super.key, required this.username, required this.token});

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  late final TaskController _ctrl;
  static const _base = BackendConfig.baseUrl;
  List<FamilyInviteInfo> _pendingInvites = const [];
  bool _invitesLoading = false;
  String? _invitesError;

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController();
    _loadFromServer();
    _loadInvites();
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

  Future<void> _loadInvites() async {
    setState(() {
      _invitesLoading = true;
      _invitesError = null;
    });
    try {
      final invites = await FamilyService.fetchChildInvites();
      if (!mounted) return;
      setState(() {
        _pendingInvites = invites;
        _invitesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _invitesError = 'Failed to load invites: $e';
        _invitesLoading = false;
      });
    }
  }

  // (Optional) persist toggle as an edit
  Future<void> _persistToggle(Task before, Task after) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/profile/block/edit'),
        headers: _jsonHeaders,
        body: json.encode({'old_block': _taskToBlock(before), 'new_block': _taskToBlock(after)}),
      );
      if (res.statusCode != 200) _toast('Server toggle failed (${res.statusCode})');
    } catch (e) {
      _toast('Toggle error: $e');
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
        'family_tag': t.familyTag,
      };

  Future<void> _handleMenuSelect(String value) async {
    switch (value) {
      case 'profile':
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        if (!mounted) return;
        _loadInvites();
        break;
      case 'signout':
        if (!mounted) return;
        AppGlobals.token = '';
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomePage()),
          (route) => false,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // No FAB, no AI/template buttons — view-only
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
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
      body: Column(
        children: [
          if (_pendingInvites.isNotEmpty) _inviteBanner(),
          if (_invitesError != null && _pendingInvites.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.4),
              child: Text(
                _invitesError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => _ChildTasksSectionViewOnly(ctrl: _ctrl, onTogglePersist: _persistToggle),
            ),
          ),
        ],
      ),
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

  Widget _inviteBanner() {
    final invite = _pendingInvites.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.9),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're invited to join \"${invite.familyName}\" (ID: ${invite.familyId}).",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text('Review from your profile page to accept or decline.'),
              ],
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
}

class _ChildTasksSectionViewOnly extends StatelessWidget {
  const _ChildTasksSectionViewOnly({required this.ctrl, required this.onTogglePersist});

  final TaskController ctrl;
  final Future<void> Function(Task before, Task after) onTogglePersist;

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
          readOnly: true,
          // Child can ONLY toggle completion and open details.
          onToggle: () async {
            final idx = ctrl.all.indexOf(t);
            if (idx == -1) return;
            final before = ctrl.all[idx];
            ctrl.toggleCompleted(idx);
            final after = ctrl.all[idx];
            await onTogglePersist(before, after); // persist toggle as edit
          },
          onEdit: null,   // disabled (IconButton will be disabled)
          onDelete: null, // disabled
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
}
