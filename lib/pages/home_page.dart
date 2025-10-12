import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class HomePage extends StatefulWidget {
  final String username;
  final String token;
  const HomePage({super.key, required this.username, required this.token});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // List to store schedule blocks
  List<Map<String, String>> blocks = [];

  final _titleController = TextEditingController();
  final _timeController = TextEditingController();
  final _descController = TextEditingController();

  // Regex to enforce HH:MM-HH:MM format
  final RegExp timeRegExp = RegExp(
    r'^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$',
  );

  void _showCreateBlockDialog() {
    _titleController.clear();
    _timeController.clear();
    _descController.clear();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Block'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(
                  labelText: 'Time (HH:MM-HH:MM)',
                ),
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

                if (title.isEmpty || time.isEmpty || desc.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All fields are required')),
                  );
                  return;
                }

                if (!timeRegExp.hasMatch(time)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Time must be HH:MM-HH:MM')),
                  );
                  return;
                }

                setState(() {
                  blocks.add({'title': title, 'time': time, 'desc': desc});
                  // Sort by start time
                  blocks.sort((a, b) {
                    final startA = a['time']!.split('-')[0];
                    final startB = b['time']!.split('-')[0];
                    return startA.compareTo(startB);
                  });
                });

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
