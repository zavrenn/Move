import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:move/dashboard_screen.dart';
import 'package:move/device_services.dart';
import 'package:move/models.dart';

void main() {
  final today = DateTime.now();
  final date = DateTime(today.year, today.month, today.day);

  DailyStepCount zeroSteps() =>
      DailyStepCount(date: date, steps: 0, syncedAt: today);

  DailySleepRecord sleep() => DailySleepRecord(
    date: date,
    sleepStart: DateTime(date.year, date.month, date.day - 1, 23, 30),
    sleepEnd: DateTime(date.year, date.month, date.day, 7, 30),
    syncedAt: today,
  );

  Widget dashboard({
    required List<DailyStepCount> steps,
    required List<DailySleepRecord> sleep,
    required bool sleepSyncFailed,
    bool stepSyncFailed = false,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: DashboardScreen(
          logs: const [],
          steps: steps,
          sleep: sleep,
          goals: DailyGoalSettings.standard,
          sleepSchedule: SleepScheduleSettings.standard,
          quickMovements: const [],
          healthStatus: HealthConnectStatus.connected,
          sleepStatus: HealthConnectStatus.connected,
          syncingSteps: false,
          syncingSleep: false,
          stepSyncFailed: stepSyncFailed,
          sleepSyncFailed: sleepSyncFailed,
          onLog: (_) {},
          onEdit: (_) {},
          onOpenHistory: () {},
          onConnectSteps: () async {},
          onConnectSleep: () async {},
          onRefreshHealthData: () async {},
          onOpenSettings: () {},
          onCustomizeQuickMoves: () {},
        ),
      ),
    );
  }

  testWidgets('missing today step record keeps score incomplete', (
    tester,
  ) async {
    await tester.pumpWidget(
      dashboard(steps: const [], sleep: [sleep()], sleepSyncFailed: false),
    );

    expect(find.text('— / 30'), findsOneWidget);
    expect(
      find.text('No step total found for today. Pull to refresh.'),
      findsOneWidget,
    );
  });

  testWidgets('sleep read failure is distinct from no session', (tester) async {
    await tester.pumpWidget(
      dashboard(steps: [zeroSteps()], sleep: const [], sleepSyncFailed: true),
    );

    expect(
      find.text('Sleep timing could not be refreshed. Pull to try again.'),
      findsOneWidget,
    );
    expect(find.text('No main sleep session found for today.'), findsNothing);
  });

  testWidgets('step read failure is distinct from no total', (tester) async {
    await tester.pumpWidget(
      dashboard(
        steps: const [],
        sleep: [sleep()],
        stepSyncFailed: true,
        sleepSyncFailed: false,
      ),
    );

    expect(
      find.text('Daily steps could not be refreshed. Pull to try again.'),
      findsOneWidget,
    );
    expect(
      find.text('No step total found for today. Pull to refresh.'),
      findsNothing,
    );
  });

  testWidgets('cached sleep score discloses a failed refresh', (tester) async {
    await tester.pumpWidget(
      dashboard(steps: [zeroSteps()], sleep: [sleep()], sleepSyncFailed: true),
    );

    expect(
      find.text('Sleep refresh failed · showing cached timing'),
      findsOneWidget,
    );
  });
}
