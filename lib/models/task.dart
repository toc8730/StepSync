class Task {
  Task({
    required this.title,
    this.steps = const [],
    this.startTime,
    this.endTime,
    this.period, // "AM" | "PM"
    this.hidden = false,
    this.completed = false,
    this.familyTag,
    this.scheduledDate,
  });

  String title;
  List<String> steps;
  String? startTime; // e.g., "1:30"
  String? endTime;   // e.g., "2:00"
  String? period;    // "AM" or "PM"
  bool hidden;
  bool completed;
  String? familyTag;
  String? scheduledDate; // YYYY-MM-DD
}
