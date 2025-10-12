import 'package:flutter/material.dart';

class Task {
  String title;
  String time; // HH:MM-HH:MM
  String description;
  bool isHidden; // true = hidden from child

  Task({required this.title, required this.time, required this.description, this.isHidden = false});
}

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Task> tasks = [];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  int _timeToMinutes(String time) {
    try {
      final parts = time.split('-')[0].split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }

  void _createTaskDialog({Task? editTask}) {
    if (editTask != null) {
      _titleController.text = editTask.title;
      _timeController.text = editTask.time;
      _descController.text = editTask.description;
    } else {
      _titleController.clear();
      _timeController.clear();
      _descController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(editTask != null ? 'Edit Task' : 'Create Task'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: _timeController, decoration: const InputDecoration(labelText: 'Time (HH:MM-HH:MM)')),
              TextField(controller: _descController, decoration: const InputDecoration(labelText: 'Description')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _titleController.clear();
              _timeController.clear();
              _descController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = _titleController.text.trim();
              final time = _timeController.text.trim();
              final desc = _descController.text.trim();

              final timePattern = RegExp(r'^\d{1,2}:\d{2}-\d{1,2}:\d{2}$');

              if (title.isEmpty || time.isEmpty || desc.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All fields are required!')));
                return;
              } else if (!timePattern.hasMatch(time)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time must be in HH:MM-HH:MM format')));
                return;
              }

              setState(() {
                if (editTask != null) {
                  editTask.title = title;
                  editTask.time = time;
                  editTask.description = desc;
                } else {
                  tasks.add(Task(title: title, time: time, description: desc));
                }
                tasks.sort((a, b) => _timeToMinutes(a.time).compareTo(_timeToMinutes(b.time)));
              });

              _titleController.clear();
              _timeController.clear();
              _descController.clear();
              Navigator.pop(context);
            },
            child: Text(editTask != null ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Parent Dashboard'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile button pressed')));
              } else if (value == 'signout') {
                Navigator.pop(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile')),
              PopupMenuItem(value: 'signout', child: Text('Sign Out')),
            ],
            icon: Row(
              children: [
                Text(widget.username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _createTaskDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Create Task'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: tasks.isEmpty
                  ? const Center(child: Text('No tasks yet'))
                  : ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return Card(
                          child: ListTile(
                            title: Text('${task.time} | ${task.title}'),
                            subtitle: task.isHidden ? const Text('[Hidden from child]') : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  tooltip: 'Edit',
                                  onPressed: () => _createTaskDialog(editTask: task),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  tooltip: 'Delete',
                                  onPressed: () {
                                    setState(() => tasks.removeAt(index));
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    task.isHidden ? Icons.visibility : Icons.visibility_off,
                                    size: 20,
                                  ),
                                  tooltip: task.isHidden ? 'Unhide' : 'Hide from Child',
                                  onPressed: () {
                                    setState(() => task.isHidden = !task.isHidden);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(task.isHidden
                                            ? 'Hidden from child dashboard'
                                            : 'Task is now visible to child'),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              // Expand/collapse to show description
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(task.title),
                                  content: Text(task.description),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    )
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
  