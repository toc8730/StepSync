import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'guided_home_page.dart';
import 'login_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Scaffold(
      body: Stack(
        children: [
          _AnimatedBackdrop(controller: _pulseController, colorScheme: scheme),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Text('Welcome to StepSync', style: titleStyle, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Make family routines collaborative, visible, and fun.',
                    style: bodyStyle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: _FloatingDevice(controller: _pulseController, colorScheme: scheme),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cards = [
                          _HighlightCard(
                            icon: Icons.auto_awesome,
                            title: 'Plan effortlessly',
                            description: 'AI + templates turn your ideas into ready-to-play routines.',
                            color: scheme.primary,
                            controller: _pulseController,
                          ),
                          _HighlightCard(
                            icon: Icons.task_alt,
                            title: 'Guide every step',
                            description: 'Visual steps, reminders, and TTS keep kids on track.',
                            color: scheme.secondary,
                            controller: _pulseController,
                          ),
                          _HighlightCard(
                            icon: Icons.family_restroom,
                            title: 'Stay in sync',
                            description: 'Parents see progress instantly and celebrate together.',
                            color: scheme.tertiary,
                            controller: _pulseController,
                          ),
                        ];

                        if (constraints.maxWidth > 900) {
                          return Column(
                            children: [
                              Expanded(child: cards[1]),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(child: cards[0]),
                                    const SizedBox(width: 16),
                                    Expanded(child: cards[2]),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(child: cards[1]),
                            const SizedBox(height: 12),
                            Expanded(child: cards[0]),
                            const SizedBox(height: 12),
                            Expanded(child: cards[2]),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const GuidedHomePage()),
                            ),
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: const Text('Get Started'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LoginPage()),
                            ),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('I already have an account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.controller,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final glow = 0.9 + controller.value * 0.2;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withOpacity(0.07),
            border: Border.all(color: color.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 18 * glow,
                spreadRadius: 1,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 42),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedBackdrop extends StatelessWidget {
  const _AnimatedBackdrop({required this.controller, required this.colorScheme});

  final AnimationController controller;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerHighest.withOpacity(0.6),
            colorScheme.surface,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _FloatingDevice extends StatelessWidget {
  const _FloatingDevice({required this.controller, required this.colorScheme});

  final AnimationController controller;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final bob = math.sin(controller.value * math.pi * 2) * 8;
        final tilt = math.sin(controller.value * math.pi * 2) * 0.02;
        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform.rotate(
            angle: tilt,
            child: CustomPaint(
              painter: _DevicePainter(colorScheme),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _DevicePainter extends CustomPainter {
  _DevicePainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final deviceWidth = size.width * 0.7;
    final deviceHeight = size.height * 0.7;
    final topLeft = Offset((size.width - deviceWidth) / 2, (size.height - deviceHeight) / 2);
    final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, deviceWidth, deviceHeight);
    final screen = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    final screenPaint = Paint()
      ..shader = LinearGradient(
        colors: [scheme.surface.withOpacity(0.95), scheme.surfaceContainerHighest.withOpacity(0.8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(screen, screenPaint);
    canvas.drawRRect(
      screen,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = scheme.primary.withOpacity(0.2)
        ..strokeWidth = 2,
    );

    final taskPaint = Paint()..color = scheme.primary.withOpacity(0.12);
    final accentPaint = Paint()..color = scheme.secondary.withOpacity(0.18);
    final checkPaint = Paint()
      ..color = scheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final padding = 20.0;
    final taskHeight = (deviceHeight - padding * 3) / 3;
    for (int i = 0; i < 3; i++) {
      final taskRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          topLeft.dx + padding,
          topLeft.dy + padding + i * (taskHeight + padding / 2),
          deviceWidth - padding * 2,
          taskHeight,
        ),
        const Radius.circular(18),
      );
      canvas.drawRRect(taskRect, i == 1 ? accentPaint : taskPaint);

      final textColor = scheme.onSurface.withOpacity(0.5);
      final sampleText = [
        'Visual checklist: get ready for school',
        'Break homework into small wins',
        'Calm-down routine before bedtime',
      ][i];
      final textSpan = TextSpan(
        text: sampleText,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      );
      final painter = TextPainter(text: textSpan, textDirection: TextDirection.ltr, maxLines: 1)
        ..layout(maxWidth: taskRect.width - 80);
      painter.paint(canvas, Offset(taskRect.left + 60, taskRect.top + 14));

      final checkCenter = Offset(taskRect.left + 28, taskRect.top + taskRect.height / 2);
      canvas.drawCircle(checkCenter, 16, Paint()..color = scheme.primary.withOpacity(0.08));
      final path = Path()
        ..moveTo(checkCenter.dx - 6, checkCenter.dy)
        ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
        ..lineTo(checkCenter.dx + 7, checkCenter.dy - 6);
      canvas.drawPath(path, checkPaint);
    }

    final baseRect = Rect.fromCenter(
      center: Offset(size.width / 2, rect.bottom + 18),
      width: deviceWidth * 0.6,
      height: 18,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, const Radius.circular(12)),
      Paint()..color = scheme.surfaceContainerHighest.withOpacity(0.8),
    );
  }

  @override
  bool shouldRepaint(_DevicePainter oldDelegate) => false;
}
