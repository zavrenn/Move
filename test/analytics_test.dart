import 'package:flutter_test/flutter_test.dart';
import 'package:move/analytics.dart';
import 'package:move/models.dart';

void main() {
  final now = DateTime(2026, 8, 25, 12);

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
}
