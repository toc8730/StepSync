// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../task_controller.dart';
import '../widgets/tasks_section.dart';
import '../widgets/task_editor_dialog.dart';
import '../widgets/template_picker_dialog.dart';
import '../widgets/ai_prompt_dialog.dart'; // <-- added
import '../models/task.dart';

import 'login_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  final String username;
  final String token;
  const HomePage({super.key, required this.username, required this.token});
  const HomePage({super.key}); //test if this is necessary

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TaskController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController();
  }

  Future<void> _handleMenuSelect(String value) async {
    switch (value) {
      case 'profile':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfilePage()),
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

  Future<void> _addTask() async {
    final Task? task = await TaskEditorDialog.show(context);
    if (task != null && mounted) {
      setState(() => _ctrl.add(task));
      _snack('Task added');
    }
  }

  Future<void> _addFromTemplate() async {
    final Task? templated = await TemplatePickerDialog.pickAndEdit(context);
    if (templated != null && mounted) {
      setState(() => _ctrl.add(templated));
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
      _snack('${tasks.length} task${tasks.length == 1 ? '' : 's'} added from AI');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          Tooltip(
            message: 'Ask AI to generate tasks',
            child: IconButton(
              icon: const Icon(Icons.auto_fix_high), // magic wand
              onPressed: _askAi,
            ),
          ),
          Tooltip(
            message: 'Choose a premade task',
            child: IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _addFromTemplate,
            ),
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
        builder: (_, __) => TasksSection(ctrl: _ctrl),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 800)),
    );
  }
}
