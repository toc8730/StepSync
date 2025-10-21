import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../task_controller.dart';
import '../widgets/tasks_section.dart';
import '../widgets/task_editor_dialog.dart';
import '../models/task.dart';
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

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController();
  }

  void _onMenu(String value) {
    switch (value) {
      case 'profile':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
        break;
      case 'signout':
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
<<<<<<< HEAD
        automaticallyImplyLeading: false,
        title: Text('Welcome, ${widget.username}!'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              String token = widget.token;
              if (value == 'profile') {
                http.get(
                  Uri.parse('http://127.0.0.1:5000/profile'),
                  headers: {'Authorization': 'Bearer $token'},
                ).then((res){
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.body)),
                  );
                });
              } else if (value == 'signout') {
                Navigator.pop(context);
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'profile', child: Text('Profile')),
              const PopupMenuItem(value: 'signout', child: Text('Sign Out')),
            ],
            icon: Row(
              children: [
                Text(
                  widget.username,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateBlockDialog,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: blocks.isEmpty
            ? const Center(child: Text('No blocks created yet.'))
            : ListView.builder(
                itemCount: blocks.length,
                itemBuilder: (context, index) {
                  final block = blocks[index];
                  return Card(
                    child: ExpansionTile(
                      title: Text('${block['time']} - ${block['title']}'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(block['desc']!),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
=======
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
>>>>>>> b502ed451c2e7f9a2688f5781e0f70bcb499c0c3
