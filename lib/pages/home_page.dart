import 'package:flutter/material.dart';
import 'notifications.dart';

class Task {
  String title;
  String description;
  String time; // e.g., "09:30-09:50"
  bool hidden = false;
  int notificationId;

  Task({
    required this.title,
    required this.description,
    required this.time,
    required this.notificationId,
  });

  /// Convert start time to DateTime for sorting
  DateTime get startDateTime {
    final start = time.split('-')[0]; // "09:30"
    final parts = start.split(':');
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }
}

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Task> tasks = [];
  int _nextNotificationId = 0;

  @override
  void initState() {
    super.initState();
    NotificationsHelper.initialize();
  }

  /// Schedule notification 5 minutes before task
  void _scheduleTaskNotification(Task task) {
    try {
      final scheduledTime = task.startDateTime.subtract(const Duration(minutes: 5));

      NotificationsHelper.scheduleNotification(
        id: task.notificationId,
        title: 'Task starting soon',
        body: '"${task.title}" starts in 5 minutes!',
        scheduledTime: scheduledTime,
      );
    } catch (e) {
      print('Failed to schedule notification: $e');
    }
  }

  /// Sort tasks by start time
  void _sortTasks() {
    tasks.sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  }

  /// Show Create Task dialog
  void _showCreateTaskDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final timeController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: timeController,
              decoration: const InputDecoration(
                labelText: 'Time (HH:MM-HH:MM)',
                hintText: '09:30-09:50',
              ),
            ),
            TextField(
              controller: descController,
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
              final task = Task(
                title: titleController.text,
                description: descController.text,
                time: timeController.text,
                notificationId: _nextNotificationId++,
              );
              setState(() {
                tasks.add(task);
                _sortTasks();
              });
              _scheduleTaskNotification(task);
              Navigator.pop(context);
            },
            child: const Text('Add Task'),
          ),
        ],
      ),
    );
  }

  /// Show Edit Task dialog
  void _showEditTaskDialog(Task task) {
    final titleController = TextEditingController(text: task.title);
    final descController = TextEditingController(text: task.description);
    final timeController = TextEditingController(text: task.time);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: timeController,
              decoration: const InputDecoration(
                labelText: 'Time (HH:MM-HH:MM)',
                hintText: '09:30-09:50',
              ),
            ),
            TextField(
              controller: descController,
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
              setState(() {
                task.title = titleController.text;
                task.description = descController.text;
                task.time = timeController.text;
                _sortTasks();
              });
              _scheduleTaskNotification(task);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        automaticallyImplyLeading: false,
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
      body: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _showCreateTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text(
                'Create Task',
                style: TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return Card(
                  color: task.hidden ? Colors.grey[300] : Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: ListTile(
                    title: Text('${task.time} - ${task.title}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.description),
                        if (task.hidden)
                          const Text(
                            'Hidden from child view',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          onPressed: () {
                            NotificationsHelper.cancelNotification(task.notificationId);
                            setState(() {
                              tasks.removeAt(index);
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showEditTaskDialog(task),
                        ),
                        IconButton(
                          icon: Icon(
                            task.hidden ? Icons.visibility : Icons.visibility_off,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              task.hidden = !task.hidden;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
