import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:move/device_services.dart';
import 'package:move/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sleep sync includes exact replacement bounds and timing-only records',
    () {
      final sync = DailySleepSync.fromPlatform({
        'startDate': '2026-08-17',
        'endDate': '2026-08-30',
        'records': [
          {
            'date': '2026-08-30',
            'sleepStart': DateTime(2026, 8, 29, 23, 30).millisecondsSinceEpoch,
            'sleepEnd': DateTime(2026, 8, 30, 7, 30).millisecondsSinceEpoch,
          },
        ],
      });

      expect(sync.startDate, DateTime(2026, 8, 17));
      expect(sync.endDate, DateTime(2026, 8, 30));
      expect(sync.records, hasLength(1));
      expect(sync.records.single.date, DateTime(2026, 8, 30));
      expect(sync.records.single.sleepStart.hour, 23);
      expect(sync.records.single.sleepEnd.hour, 7);
      expect(
        sync.records.single.toDatabaseMap(),
        isNot(contains('asleep_minutes')),
      );
    },
  );

  test('sleep sync rejects a missing records snapshot', () {
    expect(
      () => DailySleepSync.fromPlatform({
        'startDate': '2026-08-17',
        'endDate': '2026-08-30',
      }),
      throwsFormatException,
    );
  });

  test('Samsung sleep target parser rejects missing values', () {
    expect(
      () => SamsungSleepTarget.fromPlatform({'bedtimeMinutes': 23 * 60 + 30}),
      throwsFormatException,
    );
  });

  test('Samsung sleep target parser rejects malformed values', () {
    expect(
      () => SamsungSleepTarget.fromPlatform({
        'bedtimeMinutes': 23.5,
        'wakeMinutes': 7 * 60 + 30,
      }),
      throwsFormatException,
    );
    expect(
      () => SamsungSleepTarget.fromPlatform({
        'bedtimeMinutes': 23 * 60 + 30,
        'wakeMinutes': 1440,
      }),
      throwsFormatException,
    );
  });

  test(
    'Samsung step target overrides the Move fallback without replacing it',
    () {
      const fallback = DailyGoalSettings(stepGoal: 8000, movementGoal: 3);
      const target = SamsungStepTarget(steps: 12000, localDate: '2026-08-30');

      expect(
        fallback
            .resolveStepTarget(target, localDate: DateTime(2026, 8, 30))
            .stepGoal,
        12000,
      );
      expect(
        fallback
            .resolveStepTarget(target, localDate: DateTime(2026, 8, 31))
            .stepGoal,
        8000,
      );
      expect(fallback.resolveStepTarget(null).stepGoal, 8000);
      expect(fallback.stepGoal, 8000);
    },
  );

  test('Samsung step target parser rejects missing and malformed values', () {
    expect(
      () => SamsungStepTarget.fromPlatform(const {}),
      throwsFormatException,
    );
    expect(
      () => SamsungStepTarget.fromPlatform({
        'steps': 8000.5,
        'date': '2026-08-30',
      }),
      throwsFormatException,
    );
    expect(
      () => SamsungStepTarget.fromPlatform({'steps': 0, 'date': '2026-08-30'}),
      throwsFormatException,
    );
    expect(
      () => SamsungStepTarget.fromPlatform({'steps': 8000}),
      throwsFormatException,
    );
  });

  test('preferences preserve the fallback beside a cached Samsung target', () {
    final preferences = MovePreferences.fromPlatform({
      'stepGoal': 8000,
      'movementGoal': 3,
      'cachedSamsungStepGoal': 12000,
      'cachedSamsungStepGoalDate': '2026-08-30',
    });

    expect(preferences.goals.stepGoal, 8000);
    expect(preferences.cachedSamsungStepTarget?.steps, 12000);
    expect(preferences.cachedSamsungStepTarget?.localDate, '2026-08-30');
  });

  test('smart alert status parses permissions, timing, and daily state', () {
    final trackingStart = DateTime(2026, 8, 30, 8);
    final activeWindowEnd = DateTime(2026, 8, 30, 22);
    final inactiveSince = DateTime(2026, 8, 30, 10, 15);
    final lastActivity = DateTime(2026, 8, 30, 10);
    final lastAlert = DateTime(2026, 8, 30, 9);
    final nextCheck = DateTime(2026, 8, 30, 10, 30);

    final status = SmartAlertStatus.fromPlatform({
      'enabled': true,
      'notificationGranted': true,
      'stepsGranted': true,
      'backgroundReadAvailable': true,
      'backgroundReadGranted': true,
      'operational': true,
      'workerScheduled': true,
      'active': true,
      'trackingStartAt': trackingStart.millisecondsSinceEpoch,
      'activeWindowEndAt': activeWindowEnd.millisecondsSinceEpoch,
      'inactiveSince': inactiveSince.millisecondsSinceEpoch,
      'lastActivityAt': lastActivity.millisecondsSinceEpoch,
      'lastAlertAt': lastAlert.millisecondsSinceEpoch,
      'alertsToday': 2,
      'nextCheckAt': nextCheck.millisecondsSinceEpoch,
      'deferReason': 'cooldown',
    });

    expect(status.enabled, isTrue);
    expect(status.permissionsGranted, isTrue);
    expect(status.operational, isTrue);
    expect(status.workerScheduled, isTrue);
    expect(status.active, isTrue);
    expect(status.trackingStartAt, trackingStart);
    expect(status.activeWindowEndAt, activeWindowEnd);
    expect(status.inactiveSince, inactiveSince);
    expect(status.lastActivityAt, lastActivity);
    expect(status.lastAlertAt, lastAlert);
    expect(status.alertsToday, 2);
    expect(status.nextCheckAt, nextCheck);
    expect(status.deferReason, 'cooldown');
  });

  test('smart alert status safely defaults an incomplete platform map', () {
    final status = SmartAlertStatus.fromPlatform(const {});

    expect(status.enabled, isFalse);
    expect(status.permissionsGranted, isFalse);
    expect(status.needsPermissionSetup, isTrue);
    expect(status.trackingStartAt, isNull);
    expect(status.activeWindowEndAt, isNull);
    expect(status.inactiveSince, isNull);
    expect(status.lastActivityAt, isNull);
    expect(status.lastAlertAt, isNull);
    expect(status.nextCheckAt, isNull);
    expect(status.alertsToday, 0);
    expect(status.deferReason, isEmpty);
  });

  test('smart alert service uses the native compatibility contract', () async {
    const channel = MethodChannel('com.med.move/device');
    final calls = <MethodCall>[];
    final readyStatus = <String, Object?>{
      'enabled': false,
      'notificationGranted': true,
      'stepsGranted': true,
      'backgroundReadAvailable': true,
      'backgroundReadGranted': true,
      'operational': false,
      'workerScheduled': false,
      'active': false,
      'alertsToday': 0,
      'deferReason': 'disabled',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'requestNotificationPermission' => true,
            'recordMovementActivity' => null,
            _ => readyStatus,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const service = SmartAlertService();
    await service.getStatus();
    await service.requestNotificationPermission();
    await service.requestActivityPermissions();
    await service.setEnabled(true);
    final createdAt = DateTime(2026, 8, 30, 12, 34);
    await service.recordMovementActivity(createdAt: createdAt);

    expect(calls.map((call) => call.method), [
      'reminderStatus',
      'requestNotificationPermission',
      'requestSmartAlertPermissions',
      'setReminderEnabled',
      'recordMovementActivity',
    ]);
    expect(calls[3].arguments, {'enabled': true});
    expect(calls[4].arguments, {'createdAt': createdAt.millisecondsSinceEpoch});
  });
}
