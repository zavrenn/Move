import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'analytics.dart';
import 'models.dart';
import 'move_theme.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? MoveColors.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? MoveColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class MovementGlyph extends StatelessWidget {
  const MovementGlyph({super.key, required this.movement, this.size = 42});

  final MovementDefinition movement;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: movement.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: movement.color.withValues(alpha: 0.22)),
      ),
      child: Icon(movement.icon, color: movement.color, size: size * 0.48),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class LogTile extends StatelessWidget {
  const LogTile({
    super.key,
    required this.log,
    this.onTap,
    this.trailing,
    this.showDate = false,
  });

  final MovementLog log;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final movement = log.movement;
    final details = <String>[
      DateFormat(
        showDate ? 'MMM d · h:mm a' : 'h:mm a',
      ).format(log.performedAt),
      if (log.side != null) log.side!.label,
      if (log.note?.trim().isNotEmpty == true) log.note!.trim(),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              MovementGlyph(movement: movement, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatAmount(log.metric, log.amount),
                style: TextStyle(
                  color: movement.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class WeekBarChart extends StatelessWidget {
  const WeekBarChart({super.key, required this.days});

  final List<DailyActivity> days;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(
      1,
      days.fold<int>(0, (value, day) => math.max(value, day.sets)),
    );
    final today = DateTime.now();
    return SizedBox(
      height: 108,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((day) {
          final selected =
              day.date.year == today.year &&
              day.date.month == today.month &&
              day.date.day == today.day;
          final fraction = day.sets / maximum;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  day.sets == 0 ? '' : '${day.sets}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? MoveColors.primary
                        : MoveColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 62,
                  width: 20,
                  alignment: Alignment.bottomCenter,
                  decoration: BoxDecoration(
                    color: MoveColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    height: day.sets == 0 ? 5 : math.max(9, 62 * fraction),
                    width: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: selected
                            ? [MoveColors.secondary, MoveColors.primary]
                            : [
                                MoveColors.secondary.withValues(alpha: 0.45),
                                MoveColors.primary.withValues(alpha: 0.65),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat.E().format(day.date).substring(0, 1),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? MoveColors.textPrimary
                        : MoveColors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class StepBarChart extends StatelessWidget {
  const StepBarChart({super.key, required this.days});

  final List<StepDayActivity> days;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(
      1,
      days.fold<int>(0, (value, day) => math.max(value, day.steps)),
    );
    final today = DateTime.now();
    final formatter = NumberFormat.compact();
    return SizedBox(
      height: 108,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((day) {
          final selected =
              day.date.year == today.year &&
              day.date.month == today.month &&
              day.date.day == today.day;
          final fraction = day.steps / maximum;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  day.steps == 0 ? '' : formatter.format(day.steps),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? MoveColors.primary
                        : MoveColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 62,
                  width: 20,
                  alignment: Alignment.bottomCenter,
                  decoration: BoxDecoration(
                    color: MoveColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    height: day.steps == 0 ? 5 : math.max(9, 62 * fraction),
                    width: 20,
                    decoration: BoxDecoration(
                      color: selected
                          ? MoveColors.primary
                          : MoveColors.secondary.withValues(alpha: 0.64),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat.E().format(day.date).substring(0, 1),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? MoveColors.textPrimary
                        : MoveColors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: MoveColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: MoveColors.primary, size: 27),
          ),
          const SizedBox(height: 13),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
