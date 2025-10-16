// homepage.dart
import 'package:flutter/material.dart';
import 'notifications.dart';

/// Task model
class Task {
  String title;
  List<String> steps;
  String? startTime; // e.g. "1:30"
  String? endTime; // e.g. "2:00"
  String? period; // single dropdown value: "AM" or "PM"
  bool hidden;
  int notificationId;

  Task({
    required this.title,
    required this.steps,
    this.startTime,
    this.endTime,
    this.period,
    this.hidden = false,
    required this.notificationId,
  });

  /// Nicely formatted display time, inferring end period if needed
  /// returns null if either start or end missing
  String? get formattedTime {
    if (startTime == null || startTime!.trim().isEmpty) return null;
    if (endTime == null || endTime!.trim().isEmpty) return null;
    final s = startTime!.trim();
    final e = endTime!.trim();
    final p = (period ?? 'AM').toUpperCase();

    final inferredEnd = _inferEndPeriod(s, e, p);
    return '$s ${p.toLowerCase()} - $e ${inferredEnd.toLowerCase()}';
  }

  /// Infer end period using the single selected period
  /// Rules implemented:
  /// - If selected period is AM and endHour == 12 -> end is PM
  /// - If endHour < startHour -> assume it crosses to next period (e.g., 11->12 or 11->1)
  /// - Otherwise end has same period as selected
  static String _inferEndPeriod(String start, String end, String selectedPeriod) {
    try {
      final sp = selectedPeriod.toUpperCase();
      final sHour = int.parse(start.split(':')[0]);
      final eHour = int.parse(end.split(':')[0]);

      if (sp == 'AM') {
        if (eHour == 12) return 'PM';
        if (eHour < sHour) return 'PM';
        return 'AM';
      } else {
        // selected PM
        if (eHour < sHour) return 'AM'; // crosses midnight
        return 'PM';
      }
    } catch (_) {
      return selectedPeriod.toUpperCase();
    }
  }

  /// Convert the start time + period to a DateTime for sorting & scheduling.
  /// If invalid, returns a far-future date so untimed/invalid tasks appear last.
  DateTime get startDateTime {
    if (startTime == null || startTime!.trim().isEmpty || period == null) {
      return DateTime.now().add(const Duration(days: 3650));
    }
    try {
      final parts = startTime!.split(':');
      int hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final p = (period ?? 'AM').toUpperCase();
      if (p == 'AM') {
        if (hour == 12) hour = 0;
      } else {
        if (hour != 12) hour += 12;
      }
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return DateTime.now().add(const Duration(days: 3650));
    }
  }
}

/// HomePage with full task system
class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Task> tasks = [];
  int _nextNotificationId = 0;
  final Map<int, bool> expanded = {}; // expanded state per task index

  @override
  void initState() {
    super.initState();
    NotificationsHelper.initialize();
  }

  /// Schedule notification 5 minutes before start (if valid)
  void _scheduleTaskNotification(Task task) {
    if (task.startTime == null || task.period == null) return;
    try {
      final scheduled = task.startDateTime.subtract(const Duration(minutes: 5));
      if (scheduled.isAfter(DateTime.now())) {
        NotificationsHelper.scheduleNotification(
          id: task.notificationId,
          title: 'Task starting soon',
          body: '"${task.title}" starts in 5 minutes!',
          scheduledTime: scheduled,
        );
      }
    } catch (e) {
      debugPrint('Schedule failed: $e');
    }
  }

  void _cancelTaskNotification(Task task) {
    try {
      NotificationsHelper.cancelNotification(task.notificationId);
    } catch (e) {
      debugPrint('Cancel failed: $e');
    }
  }

  void _sortTasks() {
    tasks.sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  }

  // Time validation: accepts "1:30" or "01:30", minutes two digits; hours 1..12
  bool _isValidHourMinute(String input) {
    final regex = RegExp(r'^\d{1,2}:\d{2}$');
    if (!regex.hasMatch(input.trim())) return false;
    try {
      final parts = input.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      if (h < 1 || h > 12) return false;
      if (m < 0 || m > 59) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  // Validate start/end fields with single period selection and ensure end > start
  bool _areValidStartEnd(String? start, String? end, String? selectedPeriod) {
    final s = (start ?? '').trim();
    final e = (end ?? '').trim();
    final p = (selectedPeriod ?? '').toUpperCase();
    if (s.isEmpty && e.isEmpty) return true; // allowed
    if (s.isEmpty || e.isEmpty) return false; // require both
    if (!_isValidHourMinute(s) || !_isValidHourMinute(e)) return false;
    if (!(p == 'AM' || p == 'PM')) return false;

    int to24(String time, String period) {
      final parts = time.split(':');
      var hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final pp = period.toUpperCase();
      if (pp == 'AM') {
        if (hour == 12) hour = 0;
      } else {
        if (hour != 12) hour += 12;
      }
      return hour * 60 + minute;
    }

    final inferredEndPeriod = Task._inferEndPeriod(s, e, p);
    final startMin = to24(s, p);
    final endMin = to24(e, inferredEndPeriod);
    return endMin > startMin;
  }

  // ---------- Create Task Dialog ----------
  Future<void> _showCreateTaskDialog() async {
    final titleController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();
    String period = 'AM';

    List<String> steps = [''];
    int currentStep = 0;
    final stepController = TextEditingController(text: steps[currentStep]);

    void updateStepController() {
      stepController.text = steps[currentStep];
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          String rightTooltipMessage() {
            if (stepController.text.trim().isEmpty) {
              return 'Step ${currentStep + 1} cannot be empty';
            }
            return '';
          }

          bool canAddTask() {
            final titleOk = titleController.text.trim().isNotEmpty;
            final timesOk = _areValidStartEnd(startController.text, endController.text, period);
            return titleOk && timesOk;
          }

          return AlertDialog(
            title: const Text('Create Task'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title (required)
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Required',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),

                  // Time inputs: start, end, single period dropdown
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startController,
                          decoration: const InputDecoration(
                            labelText: 'Start (e.g. 1:30)',
                            hintText: '1:30',
                          ),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: period,
                        items: const [
                          DropdownMenuItem(value: 'AM', child: Text('AM')),
                          DropdownMenuItem(value: 'PM', child: Text('PM')),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            period = val ?? 'AM';
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: endController,
                          decoration: const InputDecoration(
                            labelText: 'End (e.g. 2:00)',
                            hintText: '2:00',
                          ),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // quick preview (if times valid)
                  Builder(builder: (_) {
                    final s = startController.text.trim();
                    final e = endController.text.trim();
                    if (s.isNotEmpty && e.isNotEmpty && _areValidStartEnd(s, e, period)) {
                      final inferredEnd = Task._inferEndPeriod(s, e, period);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Selected: ${s} ${period.toUpperCase()} - ${e} ${inferredEnd.toUpperCase()}',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),

                  const SizedBox(height: 12),

                  // Steps navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Step ${currentStep + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_left),
                            onPressed: currentStep == 0
                                ? null
                                : () {
                                    setDialogState(() {
                                      steps[currentStep] = stepController.text;
                                      currentStep--;
                                      updateStepController();
                                    });
                                  },
                          ),
                          Tooltip(
                            message: rightTooltipMessage(),
                            preferBelow: false,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_right),
                              onPressed: stepController.text.trim().isEmpty
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        steps[currentStep] = stepController.text;
                                        if (currentStep == steps.length - 1) steps.add('');
                                        currentStep++;
                                        updateStepController();
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  TextField(
                    controller: stepController,
                    decoration: const InputDecoration(labelText: 'Step description'),
                    onChanged: (_) => setDialogState(() {}),
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: canAddTask()
                    ? () {
                        final sText = startController.text.trim();
                        final eText = endController.text.trim();
                        if (!_areValidStartEnd(sText, eText, period)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid time: ensure both times are present and end > start, or leave both blank.')),
                          );
                          return;
                        }

                        // save step
                        steps[currentStep] = stepController.text.trim();
                        final finalSteps = steps.where((st) => st.trim().isNotEmpty).toList();

                        final newTask = Task(
                          title: titleController.text.trim(),
                          steps: finalSteps,
                          startTime: sText.isEmpty ? null : sText,
                          endTime: eText.isEmpty ? null : eText,
                          period: sText.isEmpty ? 'AM' : period,
                          notificationId: _nextNotificationId++,
                        );

                        setState(() {
                          tasks.add(newTask);
                          expanded[tasks.length - 1] = false;
                          _sortTasks();
                        });

                        _scheduleTaskNotification(newTask);
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('Add Task'),
              ),
            ],
          );
        });
      },
    );
  }

  // ---------- Edit Task Dialog ----------
  Future<void> _showEditTaskDialog(int taskIndex) async {
    final task = tasks[taskIndex];
    final titleController = TextEditingController(text: task.title);
    final startController = TextEditingController(text: task.startTime ?? '');
    final endController = TextEditingController(text: task.endTime ?? '');
    String period = (task.period ?? 'AM').toUpperCase();

    List<String> steps = List<String>.from(task.steps);
    if (steps.isEmpty) steps = [''];
    int currentStep = 0;
    final stepController = TextEditingController(text: steps[currentStep]);

    void updateStepController() {
      stepController.text = steps[currentStep];
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          String rightTooltipMessage() {
            if (stepController.text.trim().isEmpty) {
              return 'Step ${currentStep + 1} cannot be empty';
            }
            return '';
          }

          bool canSave() {
            final tiOk = titleController.text.trim().isNotEmpty;
            final timesOk = _areValidStartEnd(startController.text, endController.text, period);
            return tiOk && timesOk;
          }

          return AlertDialog(
            title: const Text('Edit Task'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title *', hintText: 'Required'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startController,
                          decoration: const InputDecoration(labelText: 'Start (e.g. 1:30)'),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: period,
                        items: const [
                          DropdownMenuItem(value: 'AM', child: Text('AM')),
                          DropdownMenuItem(value: 'PM', child: Text('PM')),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            period = val ?? 'AM';
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: endController,
                          decoration: const InputDecoration(labelText: 'End (e.g. 2:00)'),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final s = startController.text.trim();
                    final e = endController.text.trim();
                    if (s.isNotEmpty && e.isNotEmpty && _areValidStartEnd(s, e, period)) {
                      final inferredEnd = Task._inferEndPeriod(s, e, period);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Selected: ${s} ${period.toUpperCase()} - ${e} ${inferredEnd.toUpperCase()}',
                                style: const TextStyle(fontStyle: FontStyle.italic))),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Step ${currentStep + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_left),
                            onPressed: currentStep == 0
                                ? null
                                : () {
                                    setDialogState(() {
                                      steps[currentStep] = stepController.text;
                                      currentStep--;
                                      updateStepController();
                                    });
                                  },
                          ),
                          Tooltip(
                            message: rightTooltipMessage(),
                            preferBelow: false,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_right),
                              onPressed: stepController.text.trim().isEmpty
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        steps[currentStep] = stepController.text;
                                        if (currentStep == steps.length - 1) steps.add('');
                                        currentStep++;
                                        updateStepController();
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  TextField(
                    controller: stepController,
                    decoration: const InputDecoration(labelText: 'Step description'),
                    onChanged: (_) => setDialogState(() {}),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: canSave()
                    ? () {
                        final sText = startController.text.trim();
                        final eText = endController.text.trim();
                        if (!_areValidStartEnd(sText, eText, period)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid time: ensure both times present and end > start or leave both blank.')),
                          );
                          return;
                        }

                        steps[currentStep] = stepController.text.trim();
                        final finalSteps = steps.where((st) => st.trim().isNotEmpty).toList();

                        setState(() {
                          task.title = titleController.text.trim();
                          task.startTime = sText.isEmpty ? null : sText;
                          task.endTime = eText.isEmpty ? null : eText;
                          task.period = sText.isEmpty ? null : period;
                          task.steps = finalSteps;
                          _sortTasks();
                        });

                        // reschedule notification
                        _cancelTaskNotification(task);
                        _scheduleTaskNotification(task);

                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  // ---------- UI Build ----------
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile pressed')));
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
      body: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _showCreateTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Task', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: tasks.isEmpty
                ? const Center(child: Text('No tasks yet. Tap "Create Task" to add one.'))
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final isExpanded = expanded[index] ?? false;

                      return Card(
                        color: task.hidden ? Colors.grey[300] : Colors.white,
                        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        child: Column(
                          children: [
                            ListTile(
                              title: Text('${task.formattedTime ?? "(No time)"} - ${task.title}'),
                              subtitle: task.hidden
                                  ? const Text('Hidden from child view', style: TextStyle(color: Colors.red, fontSize: 12))
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                                    onPressed: () {
                                      setState(() {
                                        expanded[index] = !isExpanded;
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () => _showEditTaskDialog(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 18),
                                    onPressed: () {
                                      _cancelTaskNotification(task);
                                      setState(() {
                                        tasks.removeAt(index);
                                        expanded.remove(index);
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(task.hidden ? Icons.visibility : Icons.visibility_off, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        task.hidden = !task.hidden;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // expanded steps block (pushes other tasks)
                            if (isExpanded)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250),
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: task.steps
                                          .asMap()
                                          .entries
                                          .map((entry) => Padding(
                                                padding: const EdgeInsets.only(bottom: 8),
                                                child: Text('Step ${entry.key + 1}: ${entry.value}'),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
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
