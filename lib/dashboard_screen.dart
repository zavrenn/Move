import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'analytics.dart';
import 'device_services.dart';
import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.logs,
    required this.steps,
    required this.sleep,
    required this.goals,
    required this.sleepTarget,
    required this.quickMovements,
    required this.healthStatus,
    required this.sleepStatus,
    required this.sleepTargetStatus,
    required this.syncingSteps,
    required this.syncingSleep,
    required this.syncingSleepTarget,
    required this.stepSyncFailed,
    required this.sleepSyncFailed,
    required this.sleepTargetSyncFailed,
    required this.onLog,
    required this.onEdit,
    required this.onOpenHistory,
    required this.onConnectSteps,
    required this.onConnectSleep,
    required this.onConnectSleepTarget,
    required this.onRefreshHealthData,
    required this.onOpenSettings,
    required this.onCustomizeQuickMoves,
  });

  final List<MovementLog> logs;
  final List<DailyStepCount> steps;
  final List<DailySleepRecord> sleep;
  final DailyGoalSettings goals;
  final SamsungSleepTarget? sleepTarget;
  final List<MovementDefinition> quickMovements;
  final HealthConnectStatus? healthStatus;
  final HealthConnectStatus? sleepStatus;
  final SamsungHealthStatus? sleepTargetStatus;
  final bool syncingSteps;
  final bool syncingSleep;
  final bool syncingSleepTarget;
  final bool stepSyncFailed;
  final bool sleepSyncFailed;
  final bool sleepTargetSyncFailed;
  final ValueChanged<MovementDefinition> onLog;
  final ValueChanged<MovementLog> onEdit;
  final VoidCallback onOpenHistory;
  final Future<void> Function() onConnectSteps;
  final Future<void> Function() onConnectSleep;
  final Future<void> Function() onConnectSleepTarget;
  final Future<void> Function() onRefreshHealthData;
  final VoidCallback onOpenSettings;
  final VoidCallback onCustomizeQuickMoves;

  @override
  Widget build(BuildContext context) {
    final analytics = MoveAnalytics(logs);
    final stepAnalytics = StepAnalytics(steps);
    final sleepAnalytics = SleepAnalytics(sleep, sleepTarget);
    final activity = ActivityAnalytics(
      movements: analytics,
      steps: stepAnalytics,
    );
    final rhythmScore = RhythmScore.calculate(
      date: analytics.today,
      movements: analytics,
      steps: stepAnalytics,
      sleep: sleepAnalytics,
      goals: goals,
    );
    final recent = logs.take(3).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: onRefreshHealthData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 104),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardHeader(
                streak: activity.currentStreak,
                onSettings: onOpenSettings,
              ),
              const SizedBox(height: 18),
              Text(
                'Keep your body in motion.',
                maxLines: 1,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: MoveColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('EEEE, d MMMM').format(DateTime.now()),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              _RhythmScoreCard(
                score: rhythmScore,
                sleepActivity: sleepAnalytics.todayActivity,
                hasSleepSession:
                    sleepAnalytics.sleepOn(sleepAnalytics.today) != null,
                hasSleepTarget: sleepTarget != null,
                stepStatus: healthStatus,
                sleepStatus: sleepStatus,
                sleepTargetStatus: sleepTargetStatus,
                syncingSteps: syncingSteps,
                syncingSleep: syncingSleep,
                syncingSleepTarget: syncingSleepTarget,
                stepSyncFailed: stepSyncFailed,
                sleepSyncFailed: sleepSyncFailed,
                sleepTargetSyncFailed: sleepTargetSyncFailed,
                onConnectSteps: onConnectSteps,
                onConnectSleep: onConnectSleep,
                onConnectSleepTarget: onConnectSleepTarget,
              ),
              const SizedBox(height: 10),
              _TodayCard(
                analytics: analytics,
                stepAnalytics: stepAnalytics,
                showCachedSteps:
                    steps.isNotEmpty ||
                    healthStatus == HealthConnectStatus.connected,
                syncingSteps: syncingSteps,
                goals: goals,
              ),
              if (healthStatus == HealthConnectStatus.permissionRequired) ...[
                const SizedBox(height: 10),
                _StepsSetupCard(onConnect: onConnectSteps),
              ],
              const SizedBox(height: 22),
              const SectionTitle(
                title: 'This week',
                subtitle: 'Every logged set keeps the rhythm going',
              ),
              const SizedBox(height: 10),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                child: WeekBarChart(days: analytics.lastSevenDays),
              ),
              const SizedBox(height: 22),
              SectionTitle(
                title: 'Quick move',
                subtitle: 'Your most useful room-friendly movements',
                action: TextButton(
                  onPressed: onCustomizeQuickMoves,
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: quickMovements.map((movement) {
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
              const SizedBox(height: 22),
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
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
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
                            if (i != recent.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.streak, required this.onSettings});

  final int streak;
  final VoidCallback onSettings;

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
        IconButton(
          onPressed: onSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.tune_rounded, color: MoveColors.textSecondary),
        ),
        const SizedBox(width: 3),
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

class _RhythmScoreCard extends StatelessWidget {
  const _RhythmScoreCard({
    required this.score,
    required this.sleepActivity,
    required this.hasSleepSession,
    required this.hasSleepTarget,
    required this.stepStatus,
    required this.sleepStatus,
    required this.sleepTargetStatus,
    required this.syncingSteps,
    required this.syncingSleep,
    required this.syncingSleepTarget,
    required this.stepSyncFailed,
    required this.sleepSyncFailed,
    required this.sleepTargetSyncFailed,
    required this.onConnectSteps,
    required this.onConnectSleep,
    required this.onConnectSleepTarget,
  });

  final RhythmScore score;
  final SleepDayActivity? sleepActivity;
  final bool hasSleepSession;
  final bool hasSleepTarget;
  final HealthConnectStatus? stepStatus;
  final HealthConnectStatus? sleepStatus;
  final SamsungHealthStatus? sleepTargetStatus;
  final bool syncingSteps;
  final bool syncingSleep;
  final bool syncingSleepTarget;
  final bool stepSyncFailed;
  final bool sleepSyncFailed;
  final bool sleepTargetSyncFailed;
  final Future<void> Function() onConnectSteps;
  final Future<void> Function() onConnectSleep;
  final Future<void> Function() onConnectSleepTarget;

  @override
  Widget build(BuildContext context) {
    final total = score.total;
    final sleep = sleepActivity;
    final missingSteps = score.stepProgress == null;
    final missingSleep = score.sleepProgress == null;
    final missingSleepSession = !hasSleepSession;
    final missingSleepTarget = !hasSleepTarget;
    final syncing = syncingSteps || syncingSleep || syncingSleepTarget;
    final missingMessage = _missingMessage(
      missingSteps: missingSteps,
      missingSleep: missingSleep,
      missingSleepSession: missingSleepSession,
      missingSleepTarget: missingSleepTarget,
    );

    return SurfaceCard(
      padding: const EdgeInsets.all(17),
      borderColor: MoveColors.primary.withValues(alpha: 0.25),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF202D1C), Color(0xFF10201B)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'RHYTHM SCORE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: MoveColors.primary,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (syncing)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.auto_graph_rounded,
                  color: MoveColors.primary,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                total == null ? '—' : '$total',
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontSize: 44),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, bottom: 5),
                child: Text(
                  total == null
                      ? _waitingLabel(
                          missingSteps: missingSteps,
                          missingSleep: missingSleep,
                        )
                      : 'out of 100',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RhythmMetric(
                  label: 'MOVES',
                  points: score.movementPoints,
                  color: MoveColors.primary,
                ),
              ),
              Container(width: 1, height: 34, color: MoveColors.border),
              Expanded(
                child: _RhythmMetric(
                  label: 'STEPS',
                  points: score.stepPoints,
                  color: MoveColors.secondary,
                ),
              ),
              Container(width: 1, height: 34, color: MoveColors.border),
              Expanded(
                child: _RhythmMetric(
                  label: 'SLEEP',
                  points: score.sleepPoints,
                  color: MoveColors.sleep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (total == null) ...[
            Text(missingMessage, style: Theme.of(context).textTheme.bodySmall),
            if ((missingSteps &&
                    stepStatus == HealthConnectStatus.permissionRequired) ||
                (missingSleepSession &&
                    sleepStatus == HealthConnectStatus.permissionRequired) ||
                (missingSleepTarget && _canConnectSleepTarget)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (missingSteps &&
                      stepStatus == HealthConnectStatus.permissionRequired)
                    FilledButton.tonalIcon(
                      onPressed: syncingSteps ? null : () => onConnectSteps(),
                      icon: const Icon(Icons.directions_walk_rounded),
                      label: const Text('Connect steps'),
                    ),
                  if (missingSleepSession &&
                      sleepStatus == HealthConnectStatus.permissionRequired)
                    FilledButton.tonalIcon(
                      onPressed: syncingSleep ? null : () => onConnectSleep(),
                      icon: const Icon(Icons.bedtime_rounded),
                      label: const Text('Connect sleep sessions'),
                    ),
                  if (missingSleepTarget && _canConnectSleepTarget)
                    FilledButton.tonalIcon(
                      onPressed: syncingSleepTarget
                          ? null
                          : () => onConnectSleepTarget(),
                      icon: const Icon(Icons.bedtime_rounded),
                      label: Text(_sleepTargetActionLabel),
                    ),
                ],
              ),
            ],
          ] else ...[
            Row(
              children: [
                const Icon(
                  Icons.bedtime_rounded,
                  size: 16,
                  color: MoveColors.sleep,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sleep!.combinedDriftMinutes == 0
                        ? 'Sleep timing inside both target windows'
                        : '${formatCompactDuration(sleep.combinedDriftMinutes * 60)} sleep drift',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '+${score.balancePoints} balance',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: MoveColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (sleepSyncFailed && sleep != null) ...[
            const SizedBox(height: 8),
            Text(
              'Health Connect refresh failed · showing cached sleep timing',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: MoveColors.danger),
            ),
          ],
          if (stepSyncFailed && score.stepProgress != null) ...[
            const SizedBox(height: 8),
            Text(
              'Steps refresh failed · showing cached total',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: MoveColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  String _waitingLabel({
    required bool missingSteps,
    required bool missingSleep,
  }) {
    if (missingSteps && missingSleep) return 'waiting for health data';
    if (missingSteps) return 'waiting for steps';
    return 'waiting for sleep';
  }

  String _missingMessage({
    required bool missingSteps,
    required bool missingSleep,
    required bool missingSleepSession,
    required bool missingSleepTarget,
  }) {
    if (missingSleepTarget) {
      final targetMessage = _missingTargetMessage();
      return [
        if (missingSteps)
          stepSyncFailed
              ? 'Daily steps could not be refreshed.'
              : 'Today’s steps are missing.',
        if (missingSleepSession) _missingSessionMessage(),
        targetMessage,
      ].join(' ');
    }
    if (missingSteps && missingSleep) {
      if (stepSyncFailed && sleepSyncFailed) {
        return 'Steps and sleep timing could not be refreshed.';
      }
      if (sleepSyncFailed) {
        return 'Today’s steps are missing, and sleep timing could not be refreshed.';
      }
      if (stepSyncFailed) {
        return 'Daily steps could not be refreshed; waiting for sleep timing.';
      }
      if (stepStatus == HealthConnectStatus.permissionRequired &&
          sleepStatus == HealthConnectStatus.permissionRequired) {
        return 'Connect steps and sleep timing to complete today’s score.';
      }
      return 'Waiting for today’s steps and sleep timing.';
    }
    if (missingSteps) {
      if (stepSyncFailed) {
        return 'Daily steps could not be refreshed. Pull to try again.';
      }
      return switch (stepStatus) {
        null => 'Checking today’s step total…',
        HealthConnectStatus.connected =>
          syncingSteps
              ? 'Refreshing today’s step total…'
              : 'No step total found for today. Pull to refresh.',
        HealthConnectStatus.permissionRequired =>
          'Connect daily steps to complete today’s score.',
        HealthConnectStatus.updateRequired =>
          'Health Connect needs an update before steps can sync.',
        HealthConnectStatus.unsupported =>
          'Daily steps are unavailable on this device.',
        HealthConnectStatus.error => 'Daily steps could not be refreshed.',
      };
    }
    return _missingSessionMessage();
  }

  String _missingSessionMessage() {
    if (sleepSyncFailed) {
      return 'Health Connect sleep sessions could not be refreshed. Pull to try again.';
    }
    return switch (sleepStatus) {
      null => 'Checking last night’s sleep rhythm…',
      HealthConnectStatus.connected =>
        syncingSleep
            ? 'Refreshing last night’s sleep rhythm…'
            : 'No main sleep session found in Health Connect for today.',
      HealthConnectStatus.permissionRequired =>
        'Connect sleep timing to complete today’s score.',
      HealthConnectStatus.updateRequired =>
        'Health Connect needs an update before sleep can sync.',
      HealthConnectStatus.unsupported =>
        'Sleep timing is unavailable on this device.',
      HealthConnectStatus.error =>
        'Health Connect sleep sessions could not be refreshed.',
    };
  }

  String _missingTargetMessage() {
    if (sleepTargetSyncFailed) {
      return 'Samsung Health sleep target could not be refreshed. Pull to try again.';
    }
    return switch (sleepTargetStatus) {
      null => 'Checking your Samsung Health sleep target…',
      SamsungHealthStatus.connected =>
        syncingSleepTarget
            ? 'Refreshing your Samsung Health sleep target…'
            : 'No sleep target found in Samsung Health.',
      SamsungHealthStatus.permissionRequired =>
        'Connect Samsung Health to use your sleep target.',
      SamsungHealthStatus.noTarget =>
        'No sleep target found in Samsung Health.',
      SamsungHealthStatus.authorizationRequired =>
        'Enable Samsung Health Developer Mode to read the sleep target.',
      SamsungHealthStatus.notInstalled => 'Samsung Health is not installed.',
      SamsungHealthStatus.updateRequired =>
        'Samsung Health must be updated before the target can sync.',
      SamsungHealthStatus.disabled => 'Samsung Health is disabled.',
      SamsungHealthStatus.notInitialized =>
        'Finish setting up Samsung Health before the target can sync.',
      SamsungHealthStatus.unavailable =>
        'Samsung Health sleep target is unavailable.',
      SamsungHealthStatus.unsupported =>
        'Samsung Health sleep targets are unsupported on this device.',
      SamsungHealthStatus.error =>
        'Samsung Health sleep target could not be refreshed.',
    };
  }

  bool get _canConnectSleepTarget => switch (sleepTargetStatus) {
    SamsungHealthStatus.permissionRequired ||
    SamsungHealthStatus.notInstalled ||
    SamsungHealthStatus.updateRequired ||
    SamsungHealthStatus.disabled ||
    SamsungHealthStatus.notInitialized ||
    SamsungHealthStatus.unavailable => true,
    _ => false,
  };

  String get _sleepTargetActionLabel => switch (sleepTargetStatus) {
    SamsungHealthStatus.permissionRequired => 'Connect sleep target',
    SamsungHealthStatus.notInstalled => 'Install Samsung Health',
    SamsungHealthStatus.updateRequired => 'Update Samsung Health',
    SamsungHealthStatus.disabled => 'Enable Samsung Health',
    SamsungHealthStatus.notInitialized => 'Open Samsung Health',
    _ => 'Fix Samsung Health',
  };
}

class _RhythmMetric extends StatelessWidget {
  const _RhythmMetric({
    required this.label,
    required this.points,
    required this.color,
  });

  final String label;
  final int? points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          points == null ? '— / 30' : '$points / 30',
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.analytics,
    required this.stepAnalytics,
    required this.showCachedSteps,
    required this.syncingSteps,
    required this.goals,
  });

  final MoveAnalytics analytics;
  final StepAnalytics stepAnalytics;
  final bool showCachedSteps;
  final bool syncingSteps;
  final DailyGoalSettings goals;

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
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MoveColors.primary.withValues(alpha: 0.055),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'TODAY’S ACTIVITY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: MoveColors.primary,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (syncingSteps) ...[
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Icon(Icons.bolt_rounded, color: MoveColors.primary),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$sets',
                      style: Theme.of(
                        context,
                      ).textTheme.displaySmall?.copyWith(fontSize: 46),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 7, bottom: 5),
                      child: Text(
                        'set${sets == 1 ? '' : 's'} logged',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TodayMetric(
                        icon: Icons.repeat_rounded,
                        value: '${analytics.todayReps}',
                        label: 'reps',
                      ),
                    ),
                    Container(width: 1, height: 32, color: MoveColors.border),
                    Expanded(
                      child: _TodayMetric(
                        icon: Icons.timer_outlined,
                        value: formatCompactDuration(analytics.todaySeconds),
                        label: 'duration',
                      ),
                    ),
                    Container(width: 1, height: 32, color: MoveColors.border),
                    Expanded(
                      child: _TodayMetric(
                        icon: Icons.directions_walk_rounded,
                        value: showCachedSteps
                            ? NumberFormat.compact().format(
                                stepAnalytics.todaySteps,
                              )
                            : '—',
                        label: 'steps',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(height: 1, color: MoveColors.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InlineGoalProgress(
                        icon: Icons.task_alt_rounded,
                        label: 'MOVEMENT',
                        current: sets,
                        goal: goals.movementGoal,
                        color: MoveColors.primary,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _InlineGoalProgress(
                        icon: Icons.directions_walk_rounded,
                        label: 'STEPS',
                        current: showCachedSteps
                            ? stepAnalytics.todaySteps
                            : null,
                        goal: goals.stepGoal,
                        color: MoveColors.secondary,
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

class _InlineGoalProgress extends StatelessWidget {
  const _InlineGoalProgress({
    required this.icon,
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int? current;
  final int goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.compact();
    final progress = ((current ?? 0) / goal).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: MoveColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${current == null ? '—' : formatter.format(current)} / '
              '${formatter.format(goal)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: MoveColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            color: color,
            backgroundColor: MoveColors.surfaceHigh,
          ),
        ),
      ],
    );
  }
}

class _StepsSetupCard extends StatelessWidget {
  const _StepsSetupCard({required this.onConnect});

  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
      child: Row(
        children: [
          const Icon(
            Icons.directions_walk_rounded,
            color: MoveColors.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bring in your daily steps',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Read-only through Health Connect',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(onPressed: onConnect, child: const Text('Connect')),
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MovementGlyph(movement: movement, size: 38),
              const Spacer(),
              Icon(
                Icons.add_circle_outline_rounded,
                color: movement.color,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            movement.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
