// lib/pages/home_page.dart
import 'package:flutter/material.dart';

import '../task_controller.dart';
import '../widgets/tasks_section.dart';
import '../widgets/task_editor_dialog.dart';
import '../widgets/template_picker_dialog.dart'; // <-- added
import '../models/task.dart';

import 'login_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task added'), duration: Duration(milliseconds: 800)),
      );
    }
  }

  Future<void> _addFromTemplate() async {
    final Task? templated = await TemplatePickerDialog.pickAndEdit(context);
    if (templated != null && mounted) {
      setState(() => _ctrl.add(templated));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template added'), duration: Duration(milliseconds: 800)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          // NEW: Templates button (kept lightweight; FAB still handles normal Add)
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
        onPressed: _addTask, // same behavior as before
        child: const Icon(Icons.add),
      ),
    );
  }
}