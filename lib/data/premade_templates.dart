// lib/data/premade_templates.dart
import '../models/task_template.dart';

/// Example premade tasks. Adjust or add your own.
const List<TaskTemplate> kPremadeTemplates = [
  TaskTemplate(
    id: 'brush_teeth_morning',
    title: 'Brush your teeth',
    steps: [
      'Wet toothbrush',
      'Apply toothpaste',
      'Brush 2 minutes (circles)',
      'Rinse mouth and brush',
    ],
    start: '8:00',
    end: '8:10',
    period: 'AM',
  ),
  TaskTemplate(
    id: 'shower_morning',
    title: 'Shower',
    steps: [
      'Turn on water',
      'Shampoo + rinse',
      'Soap and rinse',
      'Dry off',
    ],
    start: '7:30',
    end: '7:45',
    period: 'AM',
  ),
  TaskTemplate(
    id: 'breakfast',
    title: 'Breakfast',
    steps: ['Prepare meal', 'Eat', 'Clean up'],
    start: '8:00',
    end: '8:20',
    period: 'AM',
  ),
  TaskTemplate(
    id: 'homework_block',
    title: 'Homework',
    steps: ['Open materials', 'Focus block', 'Review work'],
    start: '5:00',
    end: '6:00',
    period: 'PM',
  ),
  TaskTemplate(
    id: 'workout_pm',
    title: 'Workout',
    steps: ['Warm-up', 'Main set', 'Cool-down'],
    start: '4:00',
    end: '5:00',
    period: 'PM',
  ),
  TaskTemplate(
    id: 'read_pm',
    title: 'Read',
    steps: ['Pick book', 'Read', 'Bookmark next spot'],
    start: '9:00',
    end: '9:30',
    period: 'PM',
  ),
  TaskTemplate(
    id: 'walk_dog',
    title: 'Walk the dog',
    steps: ['Leash on', 'Walk loop', 'Water + treat'],
    start: '7:00',
    end: '7:20',
    period: 'PM',
  ),
];