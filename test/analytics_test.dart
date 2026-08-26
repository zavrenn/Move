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
}
