import 'package:flutter/material.dart';

import 'login_page.dart';
import 'guided_home_page.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      final t = 0.85 + (_pulseController.value * 0.15);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          _AnimatedOrb(
                            scale: t,
                            color: colorScheme.primary.withOpacity(0.08),
                            offset: const Offset(0, -30),
                          ),
                          _AnimatedOrb(
                            scale: 0.9 + (0.1 - _pulseController.value * 0.08),
                            color: colorScheme.secondary.withOpacity(0.12),
                            offset: const Offset(-20, 20),
                          ),
                          _AnimatedOrb(
                            scale: 0.6 + (_pulseController.value * 0.2),
                            color: colorScheme.tertiary.withOpacity(0.1),
                            offset: const Offset(30, 40),
                          ),
                          Icon(Icons.family_restroom, size: 96, color: colorScheme.primary),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Text(
                'Welcome to My App',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Make family routines collaborative, visible, and fun. Choose an option below to continue.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GuidedHomePage()),
                  ),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                  child: const Text('Get Started'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                  child: const Text('I already have an account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedOrb extends StatelessWidget {
  const _AnimatedOrb({required this.scale, required this.color, required this.offset});

  final double scale;
  final Color color;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
