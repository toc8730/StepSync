import 'package:flutter/material.dart';

class Task {
  String title;
  String time; // format: HH:MM-HH:MM
  String description;

  Task({required this.title, required this.time, required this.description});
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

  // Helper function to convert time string to minutes for sorting
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

  void _createTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Task'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(labelText: 'Time (HH:MM-HH:MM)'),
              ),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All fields are required!')),
                );
                return;
              } else if (!timePattern.hasMatch(time)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Time must be in HH:MM-HH:MM format')),
                );
                return;
              }

              setState(() {
                tasks.add(Task(title: title, time: time, description: desc));
                tasks.sort((a, b) => _timeToMinutes(a.time).compareTo(_timeToMinutes(b.time)));
              });

              _titleController.clear();
              _timeController.clear();
              _descController.clear();
              Navigator.pop(context);
            },
            child: const Text('Create'),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile button pressed')),
                );
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
                Text(
                  widget.username,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
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
              onPressed: _createTaskDialog,
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
                          child: ExpansionTile(
                            title: Text('${task.time} | ${task.title}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(task.description),
                              ),
                            ],
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
