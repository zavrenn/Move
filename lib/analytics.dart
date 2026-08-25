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
