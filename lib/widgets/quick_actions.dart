import 'package:flutter/material.dart';

class QuickAction {
  const QuickAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.enabled = true,
    this.highlight = false,
    this.key,
  });

  final String id;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool highlight;
  final Key? key;
}

class QuickActionRow extends StatelessWidget {
  const QuickActionRow({super.key, required this.actions, this.spacing = 12});

  final List<QuickAction> actions;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: actions
            .map(
              (action) => Padding(
                padding: EdgeInsets.only(right: action == actions.last ? 0 : spacing),
                child: KeyedSubtree(
                  key: action.key,
                  child: _ActionChip(action: action),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: action.highlight ? 1.04 : 1,
      duration: const Duration(milliseconds: 250),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: (action.enabled && action.onPressed != null) ? action.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: action.color.withOpacity(0.4)),
            color: action.highlight
                ? action.color.withOpacity(0.12)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            boxShadow: action.highlight
                ? [
                    BoxShadow(
                      color: action.color.withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: action.color),
              const SizedBox(height: 6),
              Text(
                action.label,
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
