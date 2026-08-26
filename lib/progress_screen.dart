import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'analytics.dart';
import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({
    super.key,
    required this.logs,
    required this.steps,
    required this.goals,
  });

  final List<MovementLog> logs;
  final List<DailyStepCount> steps;
  final DailyGoalSettings goals;

  @override
  Widget build(BuildContext context) {
    final analytics = MoveAnalytics(logs);
    final stepAnalytics = StepAnalytics(steps);
    final activity = ActivityAnalytics(
      movements: analytics,
      steps: stepAnalytics,
    );
    final summaries = analytics.movementSummaries;
    final recap = WeeklyRecap.calculate(
      movements: analytics,
      steps: stepAnalytics,
      goals: goals,
    );

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 104),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(
              'Consistency over intensity.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            _StreakCard(activity: activity),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactStat(
                    label: 'TOTAL SETS',
                    value: '${logs.length}',
                    icon: Icons.layers_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactStat(
                    label: 'ACTIVE DAYS',
                    value: '${activity.activeDays}',
                    icon: Icons.calendar_today_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Walking',
              subtitle: 'Automatically tracked through Health Connect',
            ),
            const SizedBox(height: 10),
            _StepsProgressCard(
              analytics: stepAnalytics,
              connected: steps.isNotEmpty,
            ),
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Weekly recap',
              subtitle: 'Your last seven days compared with the seven before',
            ),
            const SizedBox(height: 10),
            _WeeklyRecapCard(recap: recap, stepsConnected: steps.isNotEmpty),
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Consistency',
              subtitle: 'Your last 35 days',
            ),
            const SizedBox(height: 10),
            SurfaceCard(child: _ConsistencyGrid(activity: activity)),
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Top movements',
              subtitle: 'Ranked by the number of logged sets',
            ),
            const SizedBox(height: 10),
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

class _StepsProgressCard extends StatelessWidget {
  const _StepsProgressCard({required this.analytics, required this.connected});

  final StepAnalytics analytics;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.decimalPattern();
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StepMetric(
                  label: 'TODAY',
                  value: connected
                      ? formatter.format(analytics.todaySteps)
                      : '—',
                ),
              ),
              Container(width: 1, height: 39, color: MoveColors.border),
              Expanded(
                child: _StepMetric(
                  label: '7-DAY AVERAGE',
                  value: connected
                      ? formatter.format(analytics.dailyAverage)
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StepBarChart(days: analytics.lastSevenDays),
        ],
      ),
    );
  }
}

class _StepMetric extends StatelessWidget {
  const _StepMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: MoveColors.secondary),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.activity});

  final ActivityAnalytics activity;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF253319), Color(0xFF10231D)],
      ),
      borderColor: MoveColors.primary.withValues(alpha: 0.22),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: MoveColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: MoveColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${activity.currentStreak} day${activity.currentStreak == 1 ? '' : 's'}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 26),
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
                '${activity.longestStreak}',
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
      padding: const EdgeInsets.all(12),
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

class _WeeklyRecapCard extends StatelessWidget {
  const _WeeklyRecapCard({required this.recap, required this.stepsConnected});

  final WeeklyRecap recap;
  final bool stepsConnected;

  @override
  Widget build(BuildContext context) {
    final stepValue = stepsConnected
        ? NumberFormat.compact().format(recap.steps)
        : '—';
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'LAST 7 DAYS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: MoveColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              _ActiveDayTrend(recap: recap),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RecapMetric(
                  value: '${recap.activeDays}',
                  label: 'ACTIVE DAYS',
                ),
              ),
              Container(width: 1, height: 34, color: MoveColors.border),
              Expanded(
                child: _RecapMetric(value: '${recap.sets}', label: 'SETS'),
              ),
              Container(width: 1, height: 34, color: MoveColors.border),
              Expanded(
                child: _RecapMetric(value: stepValue, label: 'STEPS'),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Text('Goal days', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(
                stepsConnected ? '${recap.goalDays} / 7' : 'Connect steps',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: MoveColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stepsConnected ? recap.goalDays / 7 : 0,
              minHeight: 5,
              color: MoveColors.primary,
              backgroundColor: MoveColors.surfaceHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapMetric extends StatelessWidget {
  const _RecapMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ActiveDayTrend extends StatelessWidget {
  const _ActiveDayTrend({required this.recap});

  final WeeklyRecap recap;

  @override
  Widget build(BuildContext context) {
    final delta = recap.activeDayDelta;
    final String label;
    if (recap.previousActiveDays == 0) {
      label = recap.activeDays == 0 ? 'Start today' : 'First stretch';
    } else if (delta == 0) {
      label = 'Steady';
    } else {
      label =
          '${delta > 0 ? '+' : ''}$delta active day${delta.abs() == 1 ? '' : 's'}';
    }
    final color = delta >= 0 ? MoveColors.primary : MoveColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConsistencyGrid extends StatelessWidget {
  const _ConsistencyGrid({required this.activity});

  final ActivityAnalytics activity;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      35,
      (index) => DateTime(
        activity.today.year,
        activity.today.month,
        activity.today.day + index - 34,
      ),
    );
    final numberFormat = NumberFormat.decimalPattern();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cell = (constraints.maxWidth - (gap * 6)) / 7;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: days.map((day) {
                final sets = activity.setsOn(day);
                final steps = activity.stepsOn(day);
                final active = sets > 0 || steps > 0;
                final alpha = switch (sets) {
                  0 when steps > 0 => 0.28,
                  0 => 0.0,
                  1 => 0.28,
                  2 => 0.48,
                  3 => 0.68,
                  _ => 0.92,
                };
                final details = [
                  if (sets > 0) '$sets set${sets == 1 ? '' : 's'}',
                  if (steps > 0) '${numberFormat.format(steps)} steps',
                ];
                return Tooltip(
                  message: details.isEmpty
                      ? 'No activity'
                      : details.join(' • '),
                  child: Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: !active
                          ? MoveColors.surfaceHigh
                          : MoveColors.primary.withValues(alpha: alpha),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: !active ? MoveColors.border : Colors.transparent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          MovementGlyph(movement: summary.movement, size: 38),
          const SizedBox(width: 10),
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
                const SizedBox(height: 5),
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
