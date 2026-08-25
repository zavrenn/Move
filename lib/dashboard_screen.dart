import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'analytics.dart';
import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.logs,
    required this.onLog,
    required this.onEdit,
    required this.onOpenHistory,
  });

  final List<MovementLog> logs;
  final ValueChanged<MovementDefinition> onLog;
  final ValueChanged<MovementLog> onEdit;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final analytics = MoveAnalytics(logs);
    final recent = logs.take(3).toList();

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 118),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashboardHeader(streak: analytics.currentStreak),
            const SizedBox(height: 28),
            Text(
              'Keep your body\nin motion.',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('EEEE, d MMMM').format(DateTime.now()),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _TodayCard(analytics: analytics),
            const SizedBox(height: 30),
            const SectionTitle(
              title: 'This week',
              subtitle: 'Every logged set keeps the rhythm going',
            ),
            const SizedBox(height: 13),
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
              child: WeekBarChart(days: analytics.lastSevenDays),
            ),
            const SizedBox(height: 30),
            const SectionTitle(
              title: 'Quick move',
              subtitle: 'Your most useful room-friendly movements',
            ),
            const SizedBox(height: 13),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: MovementCatalog.quickMovements.map((movement) {
                    return SizedBox(
                      width: width,
                      child: _QuickMovementCard(
                        movement: movement,
                        onTap: () => onLog(movement),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 30),
            SectionTitle(
              title: 'Recent activity',
              subtitle: recent.isEmpty
                  ? 'Your latest logs will appear here'
                  : 'Tap a log to edit it',
              action: recent.isEmpty
                  ? null
                  : TextButton(
                      onPressed: onOpenHistory,
                      child: const Text('View all'),
                    ),
            ),
            const SizedBox(height: 10),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: recent.isEmpty
                  ? const EmptyState(
                      icon: Icons.add_task_rounded,
                      title: 'Ready when you are',
                      message:
                          'Tap a quick move or the + button to log your first set.',
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          LogTile(
                            log: recent[i],
                            onTap: () => onEdit(recent[i]),
                            showDate: true,
                          ),
                          if (i != recent.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF18251C), Color(0xFF101A16)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MoveColors.border),
          ),
          child: Image.asset('assets/icon/move_icon_foreground.png'),
        ),
        const SizedBox(width: 11),
        Text(
          'MOVE',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            letterSpacing: 3.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: MoveColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: MoveColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: MoveColors.primary,
                size: 19,
              ),
              const SizedBox(width: 6),
              Text(
                '$streak day${streak == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.analytics});

  final MoveAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final sets = analytics.todayLogs.length;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      borderColor: MoveColors.primary.withValues(alpha: 0.18),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B271C), Color(0xFF101A16)],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -55,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MoveColors.primary.withValues(alpha: 0.055),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'TODAY’S RHYTHM',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: MoveColors.primary,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.bolt_rounded, color: MoveColors.primary),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$sets',
                      style: Theme.of(
                        context,
                      ).textTheme.displaySmall?.copyWith(fontSize: 52),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 7),
                      child: Text(
                        'set${sets == 1 ? '' : 's'} logged',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _TodayMetric(
                        icon: Icons.repeat_rounded,
                        value: '${analytics.todayReps}',
                        label: 'reps',
                      ),
                    ),
                    Container(width: 1, height: 36, color: MoveColors.border),
                    Expanded(
                      child: _TodayMetric(
                        icon: Icons.timer_outlined,
                        value: formatCompactDuration(analytics.todaySeconds),
                        label: 'duration',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayMetric extends StatelessWidget {
  const _TodayMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 19, color: MoveColors.secondary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _QuickMovementCard extends StatelessWidget {
  const _QuickMovementCard({required this.movement, required this.onTap});

  final MovementDefinition movement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MovementGlyph(movement: movement, size: 40),
              const Spacer(),
              Icon(
                Icons.add_circle_outline_rounded,
                color: movement.color,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            movement.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 3),
          Text(
            movement.metric.label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
