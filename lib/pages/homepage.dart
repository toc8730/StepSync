import 'package:flutter/material.dart';
import '../task_controller.dart';
import '../widgets/tasks_section.dart';
import '../widgets/task_editor_dialog.dart';
import '../models/task.dart';
import 'login_page.dart'; // <-- add this import

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

  void _onMenu(String value) {
    switch (value) {
      case 'profile':
        // Placeholder: show a simple dialog or route later
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Profile'),
            content: const Text('Profile screen coming soon.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        break;
      case 'signout':
        // Sign out: go back to login, clear back stack so inputs are fresh
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
        actions: [
          PopupMenuButton<String>(
            onSelected: _onMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile')),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => TasksSection(ctrl: _ctrl),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final Task? task = await TaskEditorDialog.show(context);
          if (task != null) _ctrl.add(task);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}