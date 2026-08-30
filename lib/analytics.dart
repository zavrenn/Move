import 'dart:math' as math;

import 'models.dart';

class DailyActivity {
  const DailyActivity({
    required this.date,
    required this.sets,
    required this.reps,
    required this.seconds,
  });

  final DateTime date;
  final int sets;
  final int reps;
  final int seconds;
}

class MovementSummary {
  const MovementSummary({
    required this.movement,
    required this.sets,
    required this.amount,
  });

  final MovementDefinition movement;
  final int sets;
  final int amount;
}

class PeriodTotals {
  const PeriodTotals({
    required this.sets,
    required this.reps,
    required this.seconds,
  });

  final int sets;
  final int reps;
  final int seconds;
}

class StepDayActivity {
  const StepDayActivity({required this.date, required this.steps});

  final DateTime date;
  final int steps;
}

class StepAnalytics {
  StepAnalytics(this.values, {DateTime? now}) : now = now ?? DateTime.now();

  final List<DailyStepCount> values;
  final DateTime now;

  DateTime get today => DateTime(now.year, now.month, now.day);

  DailyStepCount? recordOn(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    for (final value in values) {
      if (value.date == target) return value;
    }
    return null;
  }

  int? stepsOnOrNull(DateTime date) => recordOn(date)?.steps;

  int stepsOn(DateTime date) => stepsOnOrNull(date) ?? 0;

  int get todaySteps => stepsOn(today);

  List<StepDayActivity> get lastSevenDays => List.generate(7, (index) {
    final date = DateTime(today.year, today.month, today.day + index - 6);
    return StepDayActivity(date: date, steps: stepsOn(date));
  });

  int get lastSevenTotal =>
      lastSevenDays.fold(0, (total, value) => total + value.steps);

  int get dailyAverage => (lastSevenTotal / 7).round();
}

class SleepDayActivity {
  const SleepDayActivity({
    required this.record,
    required this.bedtimeDriftMinutes,
    required this.wakeDriftMinutes,
    required this.combinedDriftMinutes,
    required this.progress,
  });

  final DailySleepRecord record;
  final int bedtimeDriftMinutes;
  final int wakeDriftMinutes;
  final int combinedDriftMinutes;
  final double progress;
}

class SleepAnalytics {
  SleepAnalytics(this.values, this.target, {DateTime? now})
    : now = now ?? DateTime.now();

  static const maxScoredDriftMinutes = 180;

  final List<DailySleepRecord> values;
  final SamsungSleepTarget? target;
  final DateTime now;

  DateTime get today => DateTime(now.year, now.month, now.day);

  DailySleepRecord? sleepOn(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    for (final value in values) {
      if (value.date == target) return value;
    }
    return null;
  }

  SleepDayActivity? activityOn(DateTime date) {
    final record = sleepOn(date);
    final sleepTarget = target;
    if (record == null || sleepTarget == null) return null;
    final bedtimeDrift = sleepTarget.bedtimeDrift(record.sleepStart);
    final wakeDrift = sleepTarget.wakeDrift(record.sleepEnd);
    final combined = math
        .sqrt((bedtimeDrift * bedtimeDrift + wakeDrift * wakeDrift) / 2)
        .round();
    return SleepDayActivity(
      record: record,
      bedtimeDriftMinutes: bedtimeDrift,
      wakeDriftMinutes: wakeDrift,
      combinedDriftMinutes: combined,
      progress: (1 - combined / maxScoredDriftMinutes).clamp(0.0, 1.0),
    );
  }

  SleepDayActivity? get todayActivity => activityOn(today);

  List<SleepDayActivity> get lastSevenRecordedDays {
    return List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day + index - 6),
    ).map(activityOn).whereType<SleepDayActivity>().toList();
  }

  int? get sevenDayAverageDrift {
    final days = lastSevenRecordedDays;
    if (days.isEmpty) return null;
    return (days.fold<int>(0, (sum, day) => sum + day.combinedDriftMinutes) /
            days.length)
        .round();
  }
}

class RhythmScore {
  const RhythmScore({
    required this.movementProgress,
    required this.stepProgress,
    required this.sleepProgress,
  });

  final double movementProgress;
  final double? stepProgress;
  final double? sleepProgress;

  int get movementPoints => (30 * movementProgress).round();

  int? get stepPoints =>
      stepProgress == null ? null : (30 * stepProgress!).round();

  int? get sleepPoints =>
      sleepProgress == null ? null : (30 * sleepProgress!).round();

  int? get balancePoints => stepProgress == null || sleepProgress == null
      ? null
      : (10 *
                math.min(
                  movementProgress,
                  math.min(stepProgress!, sleepProgress!),
                ))
            .round();

  int? get total {
    final steps = stepPoints;
    final sleep = sleepPoints;
    final balance = balancePoints;
    if (steps == null || sleep == null || balance == null) return null;
    return movementPoints + steps + sleep + balance;
  }

  factory RhythmScore.calculate({
    required DateTime date,
    required MoveAnalytics movements,
    required StepAnalytics steps,
    required SleepAnalytics sleep,
    required DailyGoalSettings goals,
  }) {
    final daySteps = steps.stepsOnOrNull(date);
    return RhythmScore(
      movementProgress: goals.movementProgress(movements.setsOn(date)),
      stepProgress: daySteps == null ? null : goals.stepProgress(daySteps),
      sleepProgress: sleep.activityOn(date)?.progress,
    );
  }
}

class ActivityAnalytics {
  const ActivityAnalytics({required this.movements, required this.steps});

  final MoveAnalytics movements;
  final StepAnalytics steps;

  DateTime get today => movements.today;

  int get activeDays => _activeDates.length;

  int get currentStreak {
    final active = _activeDates;
    if (active.isEmpty) return 0;

    var cursor = today;
    if (!active.contains(cursor)) {
      cursor = _addDays(today, -1);
      if (!active.contains(cursor)) return 0;
    }

    var streak = 0;
    while (active.contains(cursor)) {
      streak++;
      cursor = _addDays(cursor, -1);
    }
    return streak;
  }

  int get longestStreak {
    final days = _activeDates.toList()..sort();
    if (days.isEmpty) return 0;

    var longest = 1;
    var running = 1;
    for (var index = 1; index < days.length; index++) {
      if (_calendarDistance(days[index - 1], days[index]) == 1) {
        running++;
        if (running > longest) longest = running;
      } else {
        running = 1;
      }
    }
    return longest;
  }

  bool isActiveOn(DateTime date) => setsOn(date) > 0 || stepsOn(date) > 0;

  int setsOn(DateTime date) => movements.setsOn(date);

  int stepsOn(DateTime date) => steps.stepsOn(date);

  Set<DateTime> get _activeDates {
    final dates = movements.logs.map((log) => _day(log.performedAt)).toSet();
    dates.addAll(
      steps.values
          .where((value) => value.steps > 0)
          .map((value) => _day(value.date)),
    );
    return dates;
  }

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static int _calendarDistance(DateTime from, DateTime to) {
    final utcFrom = DateTime.utc(from.year, from.month, from.day);
    final utcTo = DateTime.utc(to.year, to.month, to.day);
    return utcTo.difference(utcFrom).inDays;
  }
}

class WeeklyRecap {
  const WeeklyRecap({
    required this.activeDays,
    required this.previousActiveDays,
    required this.sets,
    required this.previousSets,
    required this.steps,
    required this.previousSteps,
    required this.goalDays,
  });

  final int activeDays;
  final int previousActiveDays;
  final int sets;
  final int previousSets;
  final int steps;
  final int previousSteps;
  final int goalDays;

  int get activeDayDelta => activeDays - previousActiveDays;

  factory WeeklyRecap.calculate({
    required MoveAnalytics movements,
    required StepAnalytics steps,
    required DailyGoalSettings goals,
  }) {
    final today = movements.today;
    final currentDays = List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day + index - 6),
    );
    final previousDays = List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day + index - 13),
    );

    int setTotal(Iterable<DateTime> days) =>
        days.fold(0, (total, day) => total + movements.setsOn(day));
    int stepTotal(Iterable<DateTime> days) =>
        days.fold(0, (total, day) => total + steps.stepsOn(day));
    int activeDayTotal(Iterable<DateTime> days) => days.where((day) {
      return movements.setsOn(day) > 0 || steps.stepsOn(day) > 0;
    }).length;

    return WeeklyRecap(
      activeDays: activeDayTotal(currentDays),
      previousActiveDays: activeDayTotal(previousDays),
      sets: setTotal(currentDays),
      previousSets: setTotal(previousDays),
      steps: stepTotal(currentDays),
      previousSteps: stepTotal(previousDays),
      goalDays: currentDays.where((day) {
        return goals.isComplete(
          steps: steps.stepsOn(day),
          movements: movements.setsOn(day),
        );
      }).length,
    );
  }
}

class MoveAnalytics {
  MoveAnalytics(this.logs, {DateTime? now}) : now = now ?? DateTime.now();

  final List<MovementLog> logs;
  final DateTime now;

  DateTime get today => _day(now);

  List<MovementLog> get todayLogs =>
      logs.where((log) => _day(log.performedAt) == today).toList();

  int get todayReps => todayLogs
      .where((log) => log.metric == MetricType.reps)
      .fold(0, (sum, log) => sum + log.amount);

  int get todaySeconds => todayLogs
      .where((log) => log.metric == MetricType.duration)
      .fold(0, (sum, log) => sum + log.amount);

  int get activeDays => logs.map((log) => _day(log.performedAt)).toSet().length;

  int get currentStreak {
    final active = logs.map((log) => _day(log.performedAt)).toSet();
    if (active.isEmpty) return 0;

    var cursor = today;
    if (!active.contains(cursor)) {
      cursor = _addDays(today, -1);
      if (!active.contains(cursor)) return 0;
    }

    var streak = 0;
    while (active.contains(cursor)) {
      streak++;
      cursor = _addDays(cursor, -1);
    }
    return streak;
  }

  int get longestStreak {
    final days = logs.map((log) => _day(log.performedAt)).toSet().toList()
      ..sort();
    if (days.isEmpty) return 0;

    var longest = 1;
    var running = 1;
    for (var i = 1; i < days.length; i++) {
      if (_calendarDistance(days[i - 1], days[i]) == 1) {
        running++;
        if (running > longest) longest = running;
      } else {
        running = 1;
      }
    }
    return longest;
  }

  List<DailyActivity> get lastSevenDays {
    return List.generate(7, (index) {
      final date = _addDays(today, index - 6);
      final dayLogs = logs.where((log) => _day(log.performedAt) == date);
      return DailyActivity(
        date: date,
        sets: dayLogs.length,
        reps: dayLogs
            .where((log) => log.metric == MetricType.reps)
            .fold(0, (sum, log) => sum + log.amount),
        seconds: dayLogs
            .where((log) => log.metric == MetricType.duration)
            .fold(0, (sum, log) => sum + log.amount),
      );
    });
  }

  PeriodTotals get thisWeek {
    final monday = _addDays(today, -(today.weekday - DateTime.monday));
    return _totalsBetween(monday, _addDays(monday, 7));
  }

  PeriodTotals get previousWeek {
    final thisMonday = _addDays(today, -(today.weekday - DateTime.monday));
    return _totalsBetween(_addDays(thisMonday, -7), thisMonday);
  }

  List<MovementSummary> get movementSummaries {
    final grouped = <String, List<MovementLog>>{};
    for (final log in logs) {
      grouped.putIfAbsent(log.movementId, () => []).add(log);
    }
    final summaries = grouped.entries.map((entry) {
      final movementLogs = entry.value;
      return MovementSummary(
        movement: MovementCatalog.byId(entry.key),
        sets: movementLogs.length,
        amount: movementLogs.fold(0, (sum, log) => sum + log.amount),
      );
    }).toList();
    summaries.sort((a, b) => b.sets.compareTo(a.sets));
    return summaries;
  }

  int setsOn(DateTime date) {
    final target = _day(date);
    return logs.where((log) => _day(log.performedAt) == target).length;
  }

  PeriodTotals _totalsBetween(DateTime start, DateTime end) {
    final period = logs.where(
      (log) =>
          !log.performedAt.isBefore(start) && log.performedAt.isBefore(end),
    );
    return PeriodTotals(
      sets: period.length,
      reps: period
          .where((log) => log.metric == MetricType.reps)
          .fold(0, (sum, log) => sum + log.amount),
      seconds: period
          .where((log) => log.metric == MetricType.duration)
          .fold(0, (sum, log) => sum + log.amount),
    );
  }

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static int _calendarDistance(DateTime from, DateTime to) {
    final utcFrom = DateTime.utc(from.year, from.month, from.day);
    final utcTo = DateTime.utc(to.year, to.month, to.day);
    return utcTo.difference(utcFrom).inDays;
  }
}
