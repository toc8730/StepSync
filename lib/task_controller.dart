// lib/task_controller.dart
import 'package:flutter/material.dart';
import 'models/task.dart';
import 'services/push_notifications.dart';

class TaskController extends ChangeNotifier {
  TaskController({this.enableScheduling = true});

  final bool enableScheduling;
  final List<Task> _tasks = [];

  List<Task> get all => List.unmodifiable(_tasks);

  // ---- CRUD ----
  void add(Task t) {
    _tasks.add(t);
    _scheduleFor(t);
    notifyListeners();
  }

  // add without saving to database
  void load(Task t) {
    _tasks.add(t);
    _scheduleFor(t);
    notifyListeners();
  }

  void update(int index, Task t) {
    final old = _tasks[index];
    _cancelFor(old);
    _tasks[index] = t;
    _scheduleFor(t);
    notifyListeners();
  }

  void removeAt(int index) {
    final old = _tasks[index];
    _cancelFor(old);
    _tasks.removeAt(index);
    notifyListeners();
  }

  void toggleCompleted(int index) {
    final t = _tasks[index];
    t.completed = !t.completed;
    if (t.completed) {
      _cancelFor(t);
    } else {
      _scheduleFor(t);
    }
    notifyListeners();
  }

  void replaceAll(List<Task> tasks, {bool reschedule = true}) {
    if (reschedule) {
      for (final task in _tasks) {
        _cancelFor(task);
      }
      _tasks
        ..clear()
        ..addAll(tasks);
      for (final task in _tasks) {
        _scheduleFor(task);
      }
    } else {
      _tasks
        ..clear()
        ..addAll(tasks);
    }
    notifyListeners();
  }

  // =========================
  //  Buckets (relative to NOW)
  // =========================

  /// Earlier Today = tasks whose start time is strictly before the device's current local time.
  List<Task> get earlierToday {
    final now = DateTime.now();
    final items = _tasks.where((t) {
      if (t.completed || t.hidden) return false;
      final dt = _startDateTime(t, now);
      return dt != null && dt.isBefore(now);
    }).toList();
    items.sort(_displayComparator(now));
    return items;
  }

  /// Later Today = tasks with start times at/after now OR with no start time (to keep them visible).
  List<Task> get laterToday {
    final now = DateTime.now();
    final items = _tasks.where((t) {
      if (t.completed || t.hidden) return false;
      final dt = _startDateTime(t, now);
      return dt == null || !dt.isBefore(now);
    }).toList();
    items.sort(_displayComparator(now));
    return items;
  }

  /// Completed (sorted the same way for consistency)
  List<Task> get completed {
    final now = DateTime.now();
    final items = _tasks.where((t) => t.completed).toList();
    items.sort(_displayComparator(now));
    return items;
  }

  // =========================
  //  Scheduling helpers
  // =========================

  void _scheduleFor(Task t) {
    if (!enableScheduling) return;
    if (t.hidden || t.completed) return;
    if (!_isForToday(t)) return;
    final now = DateTime.now();
    final dt = _startDateTime(t, now);
    if (dt == null) return;
    // schedule only if in the future
    if (dt.isAfter(DateTime.now().add(const Duration(seconds: 2)))) {
      PushNotifications.scheduleTaskReminders(t, dt);
    }
  }

  void _cancelFor(Task t) {
    if (!enableScheduling) return;
    if (!_isForToday(t)) return;
    final now = DateTime.now();
    final dt = _startDateTime(t, now);
    if (dt != null) {
      PushNotifications.cancelTaskReminders(t, dt);
    }
  }

  bool _isForToday(Task t) {
    final date = (t.scheduledDate ?? '').trim();
    if (date.isEmpty) return true;
    final today = DateTime.now().toIso8601String().split('T').first;
    return date == today;
  }

  // =========================
  //  Ordering helpers
  // =========================

  /// Sort by start time (ascending); ties break by title A→Z.
  /// Tasks without a start time sort to the end of their bucket.
  Comparator<Task> _displayComparator(DateTime anchor) {
    return (a, b) {
      final aMin = _startMinutes(a, anchor);
      final bMin = _startMinutes(b, anchor);
      if (aMin != bMin) return aMin.compareTo(bMin);

      final at = a.title.toLowerCase().trim();
      final bt = b.title.toLowerCase().trim();
      return at.compareTo(bt);
    };
  }

  /// Minutes from midnight (0..1440). No time -> sentinel at end.
  int _startMinutes(Task t, DateTime anchor) {
    final dt = _startDateTime(t, anchor);
    if (dt == null) return 24 * 60 + 59;
    return dt.hour * 60 + dt.minute;
  }

  /// Convert Task.startTime ("H:MM") + period ("AM"/"PM") to a DateTime on 'anchor' date.
  DateTime? _startDateTime(Task t, DateTime anchor) {
    final hhmm = t.startTime?.trim();
    final period = t.period?.trim().toUpperCase();
    if (hhmm == null || period == null || hhmm.isEmpty || period.isEmpty) return null;

    final m = RegExp(r'^(?:[1-9]|1[0-2]):[0-5][0-9]$').firstMatch(hhmm);
    if (m == null) return null;

    final parts = hhmm.split(':');
    final hour12 = int.parse(parts[0]);       // 1..12
    final minute = int.parse(parts[1]);       // 00..59
    int hour24 = hour12 % 12;                 // 12 -> 0
    if (period == 'PM') hour24 += 12;         // PM -> +12
    DateTime base = DateTime(anchor.year, anchor.month, anchor.day);
    final dateStr = (t.scheduledDate ?? '').trim();
    if (dateStr.isNotEmpty) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        base = DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    return DateTime(base.year, base.month, base.day, hour24, minute);
  }
}
