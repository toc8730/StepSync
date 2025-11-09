import '../models/routine_template.dart';
import '../models/task.dart';

final List<RoutineTemplate> kPremadeRoutines = [
  RoutineTemplate(
    id: 'morning_ready',
    title: 'Morning Ready Routine',
    description: 'A quick start to get dressed, eat, and pack up.',
    tasks: [
      Task(title: 'Make the bed'),
      Task(title: 'Brush teeth & wash face', startTime: '7:05', endTime: '7:10', period: 'AM'),
      Task(title: 'Get dressed', startTime: '7:10', endTime: '7:20', period: 'AM'),
      Task(title: 'Eat breakfast', startTime: '7:20', endTime: '7:35', period: 'AM'),
      Task(title: 'Pack backpack', startTime: '7:35', endTime: '7:40', period: 'AM'),
    ],
  ),
  RoutineTemplate(
    id: 'after_school',
    title: 'After School Reset',
    description: 'Helps transition from school to home time.',
    tasks: [
      Task(title: 'Empty backpack & lunchbox', startTime: '3:30', endTime: '3:35', period: 'PM'),
      Task(title: 'Snack break', startTime: '3:35', endTime: '3:45', period: 'PM'),
      Task(title: 'Homework block', startTime: '3:45', endTime: '4:30', period: 'PM'),
      Task(title: 'Tidy room', startTime: '4:30', endTime: '4:40', period: 'PM'),
      Task(title: 'Prep tomorrow outfit', startTime: '4:40', endTime: '4:45', period: 'PM'),
    ],
  ),
  RoutineTemplate(
    id: 'bedtime_winddown',
    title: 'Bedtime Wind-down',
    description: 'Creates a calm evening rhythm.',
    tasks: [
      Task(title: 'Turn off screens', startTime: '8:00', endTime: '8:05', period: 'PM'),
      Task(title: 'Shower or bath', startTime: '8:05', endTime: '8:20', period: 'PM'),
      Task(title: 'Brush teeth', startTime: '8:20', endTime: '8:25', period: 'PM'),
      Task(title: 'Read for 15 minutes', startTime: '8:25', endTime: '8:40', period: 'PM'),
      Task(title: 'Lights out', startTime: '8:40', endTime: '8:45', period: 'PM'),
    ],
  ),
];
