import 'package:flutter/material.dart';
import 'notifications.dart';

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, String>> _blocks = [];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create a Block'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _timeController,
                decoration:
                    const InputDecoration(labelText: 'Time (e.g. 09:30-09:50)'),
              ),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = _titleController.text.trim();
                final time = _timeController.text.trim();
                final desc = _descController.text.trim();

                if (title.isEmpty || time.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                // Add block and sort by start time
                setState(() {
                  _blocks.add({
                    'title': title,
                    'time': time,
                    'description': desc,
                  });

                  _blocks.sort((a, b) {
                    final timeA = a['time']!.split('-')[0];
                    final timeB = b['time']!.split('-')[0];
                    return timeA.compareTo(timeB);
                  });
                });

                // Schedule notification 5 min before start
                scheduleNotification(title, time);

                _titleController.clear();
                _timeController.clear();
                _descController.clear();
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.username}!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateDialog,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'signout') {
                Navigator.pop(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'signout', child: Text('Sign Out')),
            ],
          ),
        ],
      ),
      body: _blocks.isEmpty
          ? const Center(child: Text('No blocks created yet'))
          : ListView.builder(
              itemCount: _blocks.length,
              itemBuilder: (context, index) {
                final block = _blocks[index];
                return ExpansionTile(
                  title: Text('${block['time']} — ${block['title']}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(block['description'] ?? ''),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
