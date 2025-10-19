import 'package:flutter/material.dart';
import 'models/task.dart';

class TaskController extends ChangeNotifier {
  final List<Task> _tasks = [];

  List<Task> get all => List.unmodifiable(_tasks);

  // ---- CRUD ----
  void add(Task t) { _tasks.add(t); notifyListeners(); }
  void update(int index, Task t) { _tasks[index] = t; notifyListeners(); }
  void removeAt(int index) { _tasks.removeAt(index); notifyListeners(); }
  void toggleCompleted(int index) {
    _tasks[index].completed = !_tasks[index].completed;
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

  /// Convert Task.startTime ("H:MM" or "HH:MM") + period ("AM"/"PM") to a DateTime on 'anchor' date.
  DateTime? _startDateTime(Task t, DateTime anchor) {
    final hhmm = t.startTime?.trim();
    final period = t.period?.trim().toUpperCase();
    if (hhmm == null || period == null || hhmm.isEmpty || period.isEmpty) return null;

    final m = RegExp(r'^(?:[1-9]|1[0-2]):[0-5][0-9]$').firstMatch(hhmm);
    if (m == null) return null;

    final parts = hhmm.split(':');
    final hour12 = int.parse(parts[0]);       // 1..12
    final minute = int.parse(parts[1]);       // 00..59
    int hour24 = hour12 % 12;
    if (period == 'PM') hour24 += 12;

    return DateTime(anchor.year, anchor.month, anchor.day, hour24, minute);
  }
}