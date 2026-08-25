import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'analytics.dart';
import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.logs});

  final List<MovementLog> logs;

  @override
  Widget build(BuildContext context) {
    final analytics = MoveAnalytics(logs);
    final summaries = analytics.movementSummaries;
    final thisWeek = analytics.thisWeek;
    final previousWeek = analytics.previousWeek;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 7),
            Text(
              'Consistency over intensity.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _StreakCard(analytics: analytics),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CompactStat(
                    label: 'TOTAL SETS',
                    value: '${logs.length}',
                    icon: Icons.layers_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompactStat(
                    label: 'ACTIVE DAYS',
                    value: '${analytics.activeDays}',
                    icon: Icons.calendar_today_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const SectionTitle(
              title: 'Weekly pulse',
              subtitle: 'Set count across the last seven days',
            ),
            const SizedBox(height: 13),
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _WeekTotal(label: 'THIS WEEK', value: thisWeek.sets),
                      const Spacer(),
                      _WeekChange(
                        current: thisWeek.sets,
                        previous: previousWeek.sets,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  WeekBarChart(days: analytics.lastSevenDays),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const SectionTitle(
              title: 'Consistency',
              subtitle: 'Your last 35 days',
            ),
            const SizedBox(height: 13),
            SurfaceCard(child: _ConsistencyGrid(analytics: analytics)),
            const SizedBox(height: 30),
            const SectionTitle(
              title: 'Top movements',
              subtitle: 'Ranked by the number of logged sets',
            ),
            const SizedBox(height: 13),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: summaries.isEmpty
                  ? const EmptyState(
                      icon: Icons.insights_rounded,
                      title: 'Progress starts with one log',
                      message: 'Your most frequent movements will appear here.',
                    )
                  : _MovementRanking(summaries: summaries.take(6).toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.analytics});

  final MoveAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF253319), Color(0xFF10231D)],
      ),
      borderColor: MoveColors.primary.withValues(alpha: 0.22),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: MoveColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: MoveColors.primary,
              size: 34,
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${analytics.currentStreak} day${analytics.currentStreak == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  'Current active-day streak',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${analytics.longestStreak}',
                style: const TextStyle(
                  color: MoveColors.secondary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('BEST', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: MoveColors.secondary, size: 21),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekTotal extends StatelessWidget {
  const _WeekTotal({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text('$value sets', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _WeekChange extends StatelessWidget {
  const _WeekChange({required this.current, required this.previous});

  final int current;
  final int previous;

  @override
  Widget build(BuildContext context) {
    final isUp = current >= previous;
    final String label;
    if (previous == 0) {
      label = current == 0 ? 'No activity yet' : 'Fresh week';
    } else {
      final percent = ((current - previous) / previous * 100).round().abs();
      label = '${isUp ? '+' : '-'}$percent%';
    }
    final color = isUp ? MoveColors.primary : MoveColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ConsistencyGrid extends StatelessWidget {
  const _ConsistencyGrid({required this.analytics});

  final MoveAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      35,
      (index) => DateTime(
        analytics.today.year,
        analytics.today.month,
        analytics.today.day + index - 34,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 7.0;
        final cell = (constraints.maxWidth - (gap * 6)) / 7;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: days.map((day) {
                final sets = analytics.setsOn(day);
                final alpha = switch (sets) {
                  0 => 0.0,
                  1 => 0.28,
                  2 => 0.48,
                  3 => 0.68,
                  _ => 0.92,
                };
                return Tooltip(
                  message: '$sets set${sets == 1 ? '' : 's'}',
                  child: Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: sets == 0
                          ? MoveColors.surfaceHigh
                          : MoveColors.primary.withValues(alpha: alpha),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: sets == 0
                            ? MoveColors.border
                            : Colors.transparent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Text('Less', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 7),
                for (final alpha in [0.12, 0.3, 0.55, 0.9]) ...[
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: MoveColors.primary.withValues(alpha: alpha),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
                Text('More', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MovementRanking extends StatelessWidget {
  const _MovementRanking({required this.summaries});

  final List<MovementSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final maxSets = math.max(
      1,
      summaries.fold<int>(0, (value, item) => math.max(value, item.sets)),
    );
    return Column(
      children: [
        for (var i = 0; i < summaries.length; i++) ...[
          _MovementRank(summary: summaries[i], maxSets: maxSets),
          if (i != summaries.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _MovementRank extends StatelessWidget {
  const _MovementRank({required this.summary, required this.maxSets});

  final MovementSummary summary;
  final int maxSets;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          MovementGlyph(movement: summary.movement, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.movement.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      formatAmount(summary.movement.metric, summary.amount),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: summary.movement.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.sets / maxSets,
                    minHeight: 5,
                    color: summary.movement.color,
                    backgroundColor: MoveColors.surfaceHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.sets} set${summary.sets == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
