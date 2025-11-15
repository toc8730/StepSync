import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../task_controller.dart';
import '../utils/task_step_resolver.dart';
import '../widgets/quick_actions.dart';
import '../widgets/task_editor_dialog.dart';
import '../widgets/task_tile.dart';
import 'task_detail_page.dart';
import 'login_page.dart';

class GuidedHomePage extends StatefulWidget {
  const GuidedHomePage({super.key});

  @override
  State<GuidedHomePage> createState() => _GuidedHomePageState();
}

class _GuidedHomePageState extends State<GuidedHomePage> with SingleTickerProviderStateMixin {
  late final TaskController _ctrl;
  static const Set<String> _requiredTaskActions = {'toggle', 'edit', 'delete', 'open'};
  static const Map<String, String> _taskActionDescriptions = {
    'toggle': 'Tap the checkmark to mark tasks done or undo them.',
    'edit': 'Use the pencil to tweak steps, times, or reminders.',
    'delete': 'Trash can removes a task from the schedule.',
    'open': 'Pop-out shows the detailed step viewer with images.',
  };

  final List<_GuideStep> _steps = const [
    _GuideStep(
      id: 'ai',
      title: 'Ask AI',
      description: 'Tap the wand to open the AI task helper, then close it to keep going.',
      targetId: 'ai',
      arrowAngle: 0,
    ),
    _GuideStep(
      id: 'templates',
      title: 'Premade templates',
      description: 'Pick from saved tasks. Open the list, browse, then close it to continue.',
      targetId: 'templates',
      arrowAngle: 0,
    ),
    _GuideStep(
      id: 'routines',
      title: 'Routines library',
      description: 'Launch the routines browser to see how quickly you can deploy a schedule.',
      targetId: 'routines',
      arrowAngle: 0,
    ),
    _GuideStep(
      id: 'fab',
      title: 'Add your own task',
      description: 'Use the big + button to try the editor. Save or cancel to move on.',
      targetId: 'fab',
      arrowAngle: -math.pi / 2,
    ),
    _GuideStep(
      id: 'task_edit',
      title: 'Edit a task',
      description: 'Use the pencil to tweak steps, times, or reminders.',
      targetId: 'task_edit',
      arrowAngle: math.pi,
    ),
    _GuideStep(
      id: 'task_open',
      title: 'Open pop-out view',
      description: 'Pop-out shows detailed steps, pictures, and text-to-speech.',
      targetId: 'task_open',
      arrowAngle: math.pi,
    ),
    _GuideStep(
      id: 'task_toggle',
      title: 'Mark tasks done',
      description: 'Tap the check icon to mark a task complete or undo it.',
      targetId: 'task_toggle',
      arrowAngle: math.pi,
    ),
    _GuideStep(
      id: 'task_delete',
      title: 'Delete a task',
      description: 'Trash can removes a task from today’s schedule.',
      targetId: 'task_delete',
      arrowAngle: math.pi,
    ),
  ];

  final Map<String, GlobalKey> _targetKeys = {
    'ai': GlobalKey(),
    'templates': GlobalKey(),
    'routines': GlobalKey(),
    'fab': GlobalKey(),
    'task_toggle': GlobalKey(),
    'task_edit': GlobalKey(),
    'task_delete': GlobalKey(),
    'task_open': GlobalKey(),
    'delete': GlobalKey(),
  };
  final Map<String, Offset> _arrowOffsets = {
    'ai': const Offset(2, 30),
    'templates': const Offset(2, 30),
    'routines': const Offset(0, 30),
    'fab': const Offset(-20, 0),
    'task_toggle': const Offset(-15, 60),
    'task_edit': const Offset(0, 60),
    'task_delete': const Offset(-13, 305),
    'task_open': const Offset(-15, 60),
  };
  final GlobalKey _stackKey = GlobalKey();

  final List<Task> _demoTasks = [
    Task(
      title: 'Morning Rocket Launch',
      steps: const ['Brush teeth', 'Eat breakfast', 'Pack backpack'],
      startTime: '7:00',
      endTime: '7:35',
      period: 'AM',
    ),
    Task(
      title: 'Homework Focus Block',
      steps: const ['Set timer', 'Work in bursts', 'Review answers'],
      startTime: '4:00',
      endTime: '5:00',
      period: 'PM',
    ),
    Task(
      title: 'Lights-Out Winddown',
      steps: const ['Shower', 'Read 15 mins', 'Lights out'],
      startTime: '8:30',
      endTime: '9:00',
      period: 'PM',
    ),
  ];

  int _stepIndex = 0;
  bool _completed = false;
  bool _bannerShown = false;
  bool _chromeVisible = true;
  final Set<String> _explainedTaskActions = {};
  late final AnimationController _arrowPulse;
  late final Animation<double> _arrowScale;
  Timer? _tipTimer;
  String? _tipMessage;
  Offset? _tipPosition;
  final Set<String> _claimedTargets = {};
  Task? _focusTask;

  _GuideStep get _currentStep => _steps[_stepIndex];

  @override
  void initState() {
    super.initState();
    _ctrl = TaskController(enableScheduling: false);
    for (final task in _demoTasks) {
      _ctrl.load(task);
    }
    if (_ctrl.all.isNotEmpty) {
      _focusTask = _ctrl.all.first;
    }
    _arrowPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _arrowScale = Tween<double>(begin: 0.9, end: 1.08).animate(
      CurvedAnimation(parent: _arrowPulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
    _tipTimer?.cancel();
    _arrowPulse.dispose();
    super.dispose();
  }

  void _handleActionTap(String id) {
    if (!_completed && _currentStep.id != id) return;
    switch (id) {
      case 'ai':
        _showAiPreview();
        break;
      case 'templates':
        _showTemplatePreview();
        break;
      case 'routines':
        _showRoutinePreview();
        break;
      default:
        break;
    }
  }

  Future<void> _showAiPreview() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_fix_high, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Ask AI to help'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TextField(
              decoration: InputDecoration(
                labelText: 'Prompt',
                hintText: 'e.g., after-school reset with chores',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Looks good'),
            ),
          ],
        ),
      ),
    );
    _completeStepIf('ai');
  }

  Future<void> _showTemplatePreview() async {
    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Premade templates'),
        children: const [
          ListTile(
            leading: Icon(Icons.star_outline),
            title: Text('Brush your teeth'),
            subtitle: Text('Steps included · 8:00 AM start'),
          ),
          ListTile(
            leading: Icon(Icons.star_outline),
            title: Text('Homework block'),
            subtitle: Text('Prep · focus · recap'),
          ),
          ListTile(
            leading: Icon(Icons.star_outline),
            title: Text('Evening tidy'),
            subtitle: Text('Make the room guest-ready'),
          ),
        ],
      ),
    );
    _completeStepIf('templates');
  }

  Future<void> _showRoutinePreview() async {
    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Routine library'),
        children: const [
          ListTile(
            leading: Icon(Icons.bolt),
            title: Text('Morning Ready Routine'),
            subtitle: Text('5 tasks · 35 minutes'),
          ),
          ListTile(
            leading: Icon(Icons.bolt),
            title: Text('After School Reset'),
            subtitle: Text('4 tasks · 45 minutes'),
          ),
          ListTile(
            leading: Icon(Icons.bolt),
            title: Text('Bedtime Wind-down'),
            subtitle: Text('5 tasks · 30 minutes'),
          ),
        ],
      ),
    );
    _completeStepIf('routines');
  }

  Future<void> _openTaskEditor() async {
    final task = await TaskEditorDialog.show(context);
    if (task != null) {
      _ctrl.add(task);
    }
    _completeStepIf('fab');
  }

  void _skipTour() {
    if (_completed) return;
    setState(() {
      _completed = true;
      _chromeVisible = false;
    });
    _showBanner();
  }

  void _completeStepIf(String id) {
    if (_completed) return;
    if (_currentStep.id != id) return;
    if (_stepIndex >= _steps.length - 1) {
      setState(() {
        _completed = true;
        _chromeVisible = false;
      });
      _showBanner();
    } else {
      setState(() {
        _stepIndex++;
      });
    }
  }

  void _showBanner() {
    if (!mounted || _bannerShown) return;
    _bannerShown = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        content: const Text('Changes won’t be saved until you create an account.'),
        leading: const Icon(Icons.info_outline),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            child: const Text('Create account'),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _showTip(String message, String targetId, {Offset offset = const Offset(0, -70)}) {
    _tipTimer?.cancel();
    final center = _targetCenter(targetId);
    if (center == null) return;
    setState(() {
      _tipMessage = message;
      _tipPosition = center + offset;
    });
    _tipTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _tipMessage = null;
        _tipPosition = null;
      });
    });
  }

  void _handleToggle(Task task) {
    final idx = _ctrl.all.indexOf(task);
    if (idx == -1) return;
    _ctrl.toggleCompleted(idx);
    _trackTaskAction('toggle');
  }

  Future<void> _handleEdit(Task task) async {
    final idx = _ctrl.all.indexOf(task);
    if (idx == -1) return;
    final edited = await TaskEditorDialog.show(context, initial: task);
    if (edited != null) {
      _ctrl.update(idx, edited);
      if (identical(task, _focusTask)) {
        _focusTask = _ctrl.all[idx];
      }
    }
    _trackTaskAction('edit');
  }

  Future<void> _handleDelete(Task task) async {
    final idx = _ctrl.all.indexOf(task);
    if (idx == -1) return;
    _ctrl.removeAt(idx);
    if (identical(task, _focusTask)) {
      _focusTask = _ctrl.all.isNotEmpty ? _ctrl.all.first : null;
    }
    _trackTaskAction('delete');
  }

  void _handleOpen(Task task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailPage(task: task, stepsWithImages: resolveTaskSteps(task)),
      ),
    );
    _trackTaskAction('open');
  }

  void _trackTaskAction(String key) {
    if (_completed) return;
    final targetId = switch (key) {
      'toggle' => 'task_toggle',
      'edit' => 'task_edit',
      'delete' => 'task_delete',
      'open' => 'task_open',
      _ => 'task_toggle',
    };
    if (_explainedTaskActions.add(key)) {
      final desc = _taskActionDescriptions[key];
      if (desc != null) {
        _showTip(desc, targetId);
      }
    }
    final stepId = targetId;
    if (_currentStep.id == stepId) {
      _completeStepIf(stepId);
    }
  }

  @override
  Widget build(BuildContext context) {
    _claimedTargets.clear();
    final highlightId = _completed ? null : _currentStep.id;
    final scheme = Theme.of(context).colorScheme;
    final arrowPosition = !_completed ? _arrowPositionForStep(_currentStep) : null;
    if (!_completed && arrowPosition == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final nextTitle = (_stepIndex + 1 < _steps.length) ? _steps[_stepIndex + 1].title : null;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Explore My App'),
        leadingWidth: 116,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Back to main menu',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Text('Back to menu', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
        ),
        actions: [
          if (_chromeVisible && !_completed)
            TextButton(
              onPressed: _skipTour,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: Stack(
        key: _stackKey,
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(top: kToolbarHeight + 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                QuickActionRow(
                  actions: [
                    QuickAction(
                      id: 'ai',
                      icon: Icons.auto_fix_high,
                      label: 'Ask AI',
                      color: scheme.primary,
                      onPressed: () => _handleActionTap('ai'),
                      enabled: _completed || highlightId == 'ai',
                      highlight: highlightId == 'ai',
                      key: _targetKeys['ai'],
                    ),
                    QuickAction(
                      id: 'templates',
                      icon: Icons.auto_awesome,
                      label: 'Templates',
                      color: scheme.secondary,
                      onPressed: () => _handleActionTap('templates'),
                      enabled: _completed || highlightId == 'templates',
                      highlight: highlightId == 'templates',
                      key: _targetKeys['templates'],
                    ),
                    QuickAction(
                      id: 'routines',
                      icon: Icons.bolt,
                      label: 'Routines',
                      color: scheme.tertiary,
                      onPressed: () => _handleActionTap('routines'),
                      enabled: _completed || highlightId == 'routines',
                      highlight: highlightId == 'routines',
                      key: _targetKeys['routines'],
                    ),
                    QuickAction(
                      id: 'delete',
                      icon: Icons.delete_sweep,
                      label: 'Delete all',
                      color: scheme.error,
                      onPressed: () => _showTip('Demo mode only — nothing actually deleted.', 'delete'),
                      key: _targetKeys['delete'],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      children: [
                        _sectionHeader(context, 'Earlier Today', Icons.wb_sunny_outlined, _ctrl.earlierToday.length),
                      ..._buildTaskTiles(_ctrl.earlierToday, highlightId),
                        const SizedBox(height: 12),
                        _sectionHeader(context, 'Later Today', Icons.nights_stay_outlined, _ctrl.laterToday.length),
                      ..._buildTaskTiles(_ctrl.laterToday, highlightId),
                        const SizedBox(height: 12),
                        _sectionHeader(context, 'Completed Tasks', Icons.check_circle, _ctrl.completed.length),
                      ..._buildTaskTiles(_ctrl.completed, highlightId),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_completed) _InstructionCard(step: _currentStep, nextTitle: nextTitle),
          if (arrowPosition != null)
            _ArrowPointer(
              position: arrowPosition,
              angle: _currentStep.arrowAngle,
              scale: _arrowScale,
            ),
          if (_tipMessage != null && _tipPosition != null)
            Positioned(
              left: _tipPosition!.dx - 120,
              top: _tipPosition!.dy,
              child: _TipBubble(message: _tipMessage!),
            ),
        ],
      ),
      floatingActionButton: KeyedSubtree(
        key: _targetKeys['fab'],
        child: _GuidedGlow(
          active: highlightId == 'fab',
          child: FloatingActionButton.extended(
            onPressed: _completed || highlightId == 'fab' ? _openTaskEditor : null,
            icon: const Icon(Icons.add),
            label: const Text('New task'),
          ),
        ),
      ),
    );
  }

  Offset? _targetCenter(String targetId) {
    final key = _targetKeys[targetId];
    final stackContext = _stackKey.currentContext;
    if (key == null || stackContext == null) return null;
    final targetContext = key.currentContext;
    if (targetContext == null) return null;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (targetBox == null || stackBox == null || !targetBox.attached || !stackBox.attached) return null;
    final global = targetBox.localToGlobal(targetBox.size.center(Offset.zero));
    return stackBox.globalToLocal(global);
  }

  Offset? _arrowPositionForStep(_GuideStep step) {
    final targetCenter = _targetCenter(step.targetId);
    if (targetCenter == null) return null;
    const iconSize = 48.0;
    final direction = Offset(-math.sin(step.arrowAngle), math.cos(step.arrowAngle));
    final iconCenter = targetCenter - direction * 72;
    final tweak = _arrowOffsets[step.targetId] ?? Offset.zero;
    return iconCenter - const Offset(iconSize / 2, iconSize / 2) + tweak;
  }

  GlobalKey? _claimTarget(String id) {
    if (id.isEmpty) return null;
    if (_claimedTargets.contains(id)) return null;
    _claimedTargets.add(id);
    return _targetKeys[id];
  }

  List<Widget> _buildTaskTiles(List<Task> tasks, String? highlightId) {
    if (tasks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No tasks in this section yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ];
    }
    return tasks.asMap().entries.map((entry) {
      final task = entry.value;
      final bool isFocus = identical(task, _focusTask);
      final bool highlightTile = isFocus &&
          (highlightId == 'task_edit' ||
              highlightId == 'task_open' ||
              highlightId == 'task_toggle' ||
              highlightId == 'task_delete');
      final toggleKey = highlightTile && highlightId == 'task_toggle' ? _claimTarget('task_toggle') : null;
      final editKey = highlightTile && highlightId == 'task_edit' ? _claimTarget('task_edit') : null;
      final deleteKey = highlightTile && highlightId == 'task_delete' ? _claimTarget('task_delete') : null;
      final openKey = highlightTile && highlightId == 'task_open' ? _claimTarget('task_open') : null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _GuidedGlow(
          active: highlightTile,
          child: TaskTile(
            task: task,
            onToggle: () => _handleToggle(task),
            onEdit: () => _handleEdit(task),
            onDelete: () => _handleDelete(task),
            onOpen: () => _handleOpen(task),
            strikeThroughWhenCompleted: true,
            stepsWithImages: resolveTaskSteps(task),
            toggleButtonKey: toggleKey,
            editButtonKey: editKey,
            deleteButtonKey: deleteKey,
            openButtonKey: openKey,
          ),
        ),
      );
    }).toList();
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon, int count) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  '$count task${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.step, this.nextTitle});

  final _GuideStep step;
  final String? nextTitle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(step.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(step.description),
              if (nextTitle != null) ...[
                const SizedBox(height: 8),
                Text('Next: $nextTitle', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowPointer extends StatelessWidget {
  const _ArrowPointer({required this.position, required this.angle, required this.scale});

  final Offset position;
  final double angle;
  final Animation<double> scale;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: scale,
          builder: (context, child) {
            return Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale.value,
                child: child,
              ),
            );
          },
          child: Icon(
            Icons.arrow_downward,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _GuidedGlow extends StatelessWidget {
  const _GuidedGlow({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.03 : 1,
      duration: const Duration(milliseconds: 200),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 3,
                  ),
                ]
              : const [],
        ),
        child: child,
      ),
    );
  }
}

class _TipBubble extends StatelessWidget {
  const _TipBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _GuideStep {
  const _GuideStep({
    required this.id,
    required this.title,
    required this.description,
    required this.targetId,
    required this.arrowAngle,
  });
  final String id;
  final String title;
  final String description;
  final String targetId;
  final double arrowAngle;
}
