import 'package:flutter_test/flutter_test.dart';
import 'package:move/analytics.dart';
import 'package:move/models.dart';

void main() {
  final now = DateTime(2026, 8, 25, 12);
  const target = SamsungSleepTarget(
    bedtimeMinutes: 23 * 60 + 30,
    wakeMinutes: 7 * 60 + 30,
  );

  MovementLog logOn(
    DateTime date, {
    int amount = 10,
    MetricType metric = MetricType.reps,
  }) {
    return MovementLog(
      movementId: metric == MetricType.reps ? 'squat' : 'plank',
      metric: metric,
      amount: amount,
      performedAt: date,
      createdAt: date,
    );
  }

  DailySleepRecord sleepEndingOn(
    DateTime date, {
    required DateTime start,
    required DateTime end,
  }) {
    return DailySleepRecord(
      date: date,
      sleepStart: start,
      sleepEnd: end,
      syncedAt: now,
    );
  }

  test('current streak includes consecutive days ending today', () {
    final analytics = MoveAnalytics([
      logOn(DateTime(2026, 8, 25, 9)),
      logOn(DateTime(2026, 8, 24, 18)),
      logOn(DateTime(2026, 8, 23, 14)),
      logOn(DateTime(2026, 8, 20, 14)),
    ], now: now);

    expect(analytics.currentStreak, 3);
    expect(analytics.longestStreak, 3);
  });

  test('streak remains active when today is not finished yet', () {
    final analytics = MoveAnalytics([
      logOn(DateTime(2026, 8, 24)),
      logOn(DateTime(2026, 8, 23)),
    ], now: now);

    expect(analytics.currentStreak, 2);
  });

  test('combined activity counts step-only days in every streak metric', () {
    final movements = MoveAnalytics([
      logOn(DateTime(2026, 8, 25)),
      logOn(DateTime(2026, 8, 22)),
    ], now: now);
    final steps = StepAnalytics([
      DailyStepCount(date: DateTime(2026, 8, 24), steps: 4200, syncedAt: now),
      DailyStepCount(date: DateTime(2026, 8, 23), steps: 1800, syncedAt: now),
      DailyStepCount(date: DateTime(2026, 8, 21), steps: 0, syncedAt: now),
    ], now: now);
    final activity = ActivityAnalytics(movements: movements, steps: steps);

    expect(activity.activeDays, 4);
    expect(activity.currentStreak, 4);
    expect(activity.longestStreak, 4);
    expect(activity.isActiveOn(DateTime(2026, 8, 24)), isTrue);
    expect(activity.isActiveOn(DateTime(2026, 8, 21)), isFalse);
  });

  test('repetitions and duration remain separate', () {
    final analytics = MoveAnalytics([
      logOn(DateTime(2026, 8, 25, 9), amount: 20),
      logOn(DateTime(2026, 8, 25, 10), amount: 45, metric: MetricType.duration),
    ], now: now);

    expect(analytics.todayLogs.length, 2);
    expect(analytics.todayReps, 20);
    expect(analytics.todaySeconds, 45);
  });

  test(
    'step analytics fills missing days and calculates seven-day average',
    () {
      final analytics = StepAnalytics([
        DailyStepCount(date: DateTime(2026, 8, 25), steps: 7000, syncedAt: now),
        DailyStepCount(date: DateTime(2026, 8, 24), steps: 3500, syncedAt: now),
      ], now: now);

      expect(analytics.todaySteps, 7000);
      expect(analytics.lastSevenDays.length, 7);
      expect(analytics.lastSevenTotal, 10500);
      expect(analytics.dailyAverage, 1500);
    },
  );

  test('daily goals keep step and movement progress independent', () {
    const goals = DailyGoalSettings(stepGoal: 8000, movementGoal: 3);

    expect(goals.stepProgress(4000), 0.5);
    expect(goals.movementProgress(2), closeTo(2 / 3, 0.001));
    expect(goals.isComplete(steps: 8000, movements: 2), isFalse);
    expect(goals.isComplete(steps: 8000, movements: 3), isTrue);
  });

  test('weekly recap compares rolling seven-day periods and goal days', () {
    final movements = MoveAnalytics([
      logOn(DateTime(2026, 8, 25, 9)),
      logOn(DateTime(2026, 8, 24, 9)),
      logOn(DateTime(2026, 8, 18, 9)),
    ], now: now);
    final steps = StepAnalytics([
      DailyStepCount(date: DateTime(2026, 8, 25), steps: 6000, syncedAt: now),
      DailyStepCount(date: DateTime(2026, 8, 24), steps: 4000, syncedAt: now),
      DailyStepCount(date: DateTime(2026, 8, 23), steps: 5500, syncedAt: now),
      DailyStepCount(date: DateTime(2026, 8, 18), steps: 5000, syncedAt: now),
    ], now: now);

    final recap = WeeklyRecap.calculate(
      movements: movements,
      steps: steps,
      goals: const DailyGoalSettings(stepGoal: 5000, movementGoal: 1),
    );

    expect(recap.activeDays, 3);
    expect(recap.previousActiveDays, 1);
    expect(recap.sets, 2);
    expect(recap.previousSets, 1);
    expect(recap.steps, 15500);
    expect(recap.previousSteps, 5000);
    expect(recap.goalDays, 1);
  });

  test('Samsung target creates fixed windows that wrap around midnight', () {
    const wrappedTarget = SamsungSleepTarget(
      bedtimeMinutes: 23 * 60 + 45,
      wakeMinutes: 7 * 60 + 15,
    );

    expect(wrappedTarget.bedtimeStartMinutes, 23 * 60 + 15);
    expect(wrappedTarget.bedtimeEndMinutes, 15);
    expect(wrappedTarget.wakeStartMinutes, 6 * 60 + 45);
    expect(wrappedTarget.wakeEndMinutes, 7 * 60 + 45);
  });

  test('sleep target measures only drift outside its fixed windows', () {
    expect(target.bedtimeDrift(DateTime(2026, 8, 24, 23, 30)), 0);
    expect(target.bedtimeDrift(DateTime(2026, 8, 25, 0, 0)), 0);
    expect(target.bedtimeDrift(DateTime(2026, 8, 25, 0, 45)), 45);
    expect(target.wakeDrift(DateTime(2026, 8, 25, 7, 30)), 0);
    expect(target.wakeDrift(DateTime(2026, 8, 25, 9, 15)), 75);
  });

  test('sleep rhythm combines bedtime and wake drift with RMS', () {
    final analytics = SleepAnalytics(
      [
        sleepEndingOn(
          DateTime(2026, 8, 25),
          start: DateTime(2026, 8, 25, 1),
          end: DateTime(2026, 8, 25, 9),
        ),
      ],
      target,
      now: now,
    );

    final activity = analytics.todayActivity!;
    expect(activity.bedtimeDriftMinutes, 60);
    expect(activity.wakeDriftMinutes, 60);
    expect(activity.combinedDriftMinutes, 60);
    expect(activity.progress, closeTo(2 / 3, 0.001));
  });

  test('rhythm score rewards all three pillars plus balance', () {
    final movements = MoveAnalytics([
      logOn(DateTime(2026, 8, 25, 9)),
      logOn(DateTime(2026, 8, 25, 10)),
      logOn(DateTime(2026, 8, 25, 11)),
    ], now: now);
    final steps = StepAnalytics([
      DailyStepCount(date: DateTime(2026, 8, 25), steps: 8000, syncedAt: now),
    ], now: now);
    final sleep = SleepAnalytics(
      [
        sleepEndingOn(
          DateTime(2026, 8, 25),
          start: DateTime(2026, 8, 24, 23, 30),
          end: DateTime(2026, 8, 25, 7, 30),
        ),
      ],
      target,
      now: now,
    );

    final score = RhythmScore.calculate(
      date: DateTime(2026, 8, 25),
      movements: movements,
      steps: steps,
      sleep: sleep,
      goals: DailyGoalSettings.standard,
    );

    expect(score.movementPoints, 30);
    expect(score.stepPoints, 30);
    expect(score.sleepPoints, 30);
    expect(score.balancePoints, 10);
    expect(score.total, 100);
  });

  test('rhythm score remains incomplete when sleep is missing', () {
    final movements = MoveAnalytics(const [], now: now);
    final steps = StepAnalytics([
      DailyStepCount(date: DateTime(2026, 8, 25), steps: 0, syncedAt: now),
    ], now: now);
    final sleep = SleepAnalytics(const [], target, now: now);

    final score = RhythmScore.calculate(
      date: DateTime(2026, 8, 25),
      movements: movements,
      steps: steps,
      sleep: sleep,
      goals: DailyGoalSettings.standard,
    );

    expect(score.total, isNull);
    expect(score.stepPoints, 0);
    expect(score.sleepPoints, isNull);
  });

  test('rhythm score remains incomplete when today step data is missing', () {
    final movements = MoveAnalytics(const [], now: now);
    final steps = StepAnalytics(const [], now: now);
    final sleep = SleepAnalytics(
      [
        sleepEndingOn(
          DateTime(2026, 8, 25),
          start: DateTime(2026, 8, 24, 23, 30),
          end: DateTime(2026, 8, 25, 7, 30),
        ),
      ],
      target,
      now: now,
    );

    final score = RhythmScore.calculate(
      date: DateTime(2026, 8, 25),
      movements: movements,
      steps: steps,
      sleep: sleep,
      goals: DailyGoalSettings.standard,
    );

    expect(steps.recordOn(DateTime(2026, 8, 25)), isNull);
    expect(score.stepPoints, isNull);
    expect(score.sleepPoints, 30);
    expect(score.balancePoints, isNull);
    expect(score.total, isNull);
  });

  test('an explicit zero step record is valid score data', () {
    final zero = DailyStepCount(
      date: DateTime(2026, 8, 25),
      steps: 0,
      syncedAt: now,
    );
    final steps = StepAnalytics([zero], now: now);
    final score = RhythmScore.calculate(
      date: DateTime(2026, 8, 25),
      movements: MoveAnalytics(const [], now: now),
      steps: steps,
      sleep: SleepAnalytics(
        [
          sleepEndingOn(
            DateTime(2026, 8, 25),
            start: DateTime(2026, 8, 24, 23, 30),
            end: DateTime(2026, 8, 25, 7, 30),
          ),
        ],
        target,
        now: now,
      ),
      goals: DailyGoalSettings.standard,
    );

    expect(steps.recordOn(DateTime(2026, 8, 25)), same(zero));
    expect(score.stepPoints, 0);
    expect(score.balancePoints, 0);
    expect(score.total, 30);
  });

  test('rhythm score stays incomplete without a Samsung sleep target', () {
    final sleep = SleepAnalytics(
      [
        sleepEndingOn(
          DateTime(2026, 8, 25),
          start: DateTime(2026, 8, 24, 23, 30),
          end: DateTime(2026, 8, 25, 7, 30),
        ),
      ],
      null,
      now: now,
    );
    final score = RhythmScore.calculate(
      date: DateTime(2026, 8, 25),
      movements: MoveAnalytics(const [], now: now),
      steps: StepAnalytics([
        DailyStepCount(date: DateTime(2026, 8, 25), steps: 0, syncedAt: now),
      ], now: now),
      sleep: sleep,
      goals: DailyGoalSettings.standard,
    );

    expect(sleep.sleepOn(DateTime(2026, 8, 25)), isNotNull);
    expect(sleep.todayActivity, isNull);
    expect(score.sleepPoints, isNull);
    expect(score.balancePoints, isNull);
    expect(score.total, isNull);
  });
}
