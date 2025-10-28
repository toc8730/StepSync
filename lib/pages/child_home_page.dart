import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/data/globals.dart';
import '../task_controller.dart';
import '../widgets/tasks_section.dart';
import '../models/task.dart';

import 'join_family_page.dart';
import 'login_page.dart';

/// Read-only home for CHILD accounts:
/// - No Add Task FAB
/// - No AI / Template actions
/// - Menu only allows Join Family + Sign out
/// - Uses the same TasksSection rendering as parent, but readOnly=true hides
///   edit/delete/complete controls inside each row.
class ChildHomePage extends StatefulWidget {
  final String username;
  final String token;
  const ChildHomePage({super.key, required this.username, required this.token});

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  late final TaskController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController();

    // Load tasks from your backend to mirror parent behavior
    http.get(
      Uri.parse('http://127.0.0.1:5000/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      },
    ).then((res) {
      try {
        final body = json.decode(res.body);
        final dynamic scheduleBlocks = body['schedule_blocks'];
        if (scheduleBlocks is List) {
          for (final block in scheduleBlocks) {
            if (block is Map<String, dynamic>) {
              _ctrl.load(
                Task(
                  title: (block['title'] ?? '').toString(),
                  startTime: (block['startTime'] ?? '').toString(),
                  endTime: (block['endTime'] ?? '').toString(),
                  period: (block['period'] ?? '').toString(),
                  hidden: (block['hidden'] ?? false) == true,
                  completed: (block['completed'] ?? false) == true,
                ),
              );
            }
          }
        }
      } catch (_) {
        // keep UI responsive even if decode fails
      }
    });
  }

  Future<void> _handleMenuSelect(String value) async {
    switch (value) {
      case 'join_family':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const JoinFamilyPage()),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Preserve your app title styling
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: _handleMenuSelect,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'join_family',
                child: ListTile(
                  leading: Icon(Icons.group_add_outlined),
                  title: Text('Join Family'),
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

      // Now truly read-only inside the list
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => TasksSection(ctrl: _ctrl, readOnly: true),
      ),

      // No FAB — children cannot add tasks
      floatingActionButton: null,
    );
  }
}