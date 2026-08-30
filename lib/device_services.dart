import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

enum HealthConnectStatus {
  connected,
  permissionRequired,
  updateRequired,
  unsupported,
  error,
}

enum SamsungHealthStatus {
  connected,
  permissionRequired,
  noTarget,
  authorizationRequired,
  notInstalled,
  updateRequired,
  disabled,
  notInitialized,
  unavailable,
  unsupported,
  error,
}

class SamsungHealthService {
  const SamsungHealthService();

  static const _channel = MethodChannel('com.med.move/device');

  Future<SamsungHealthStatus> getSleepTargetStatus() async {
    if (!Platform.isAndroid) return SamsungHealthStatus.unsupported;
    try {
      final value = await _channel.invokeMethod<String>(
        'samsungSleepTargetStatus',
      );
      return switch (value) {
        'connected' => SamsungHealthStatus.connected,
        'permissionRequired' => SamsungHealthStatus.permissionRequired,
        'authorizationRequired' => SamsungHealthStatus.authorizationRequired,
        'notInstalled' => SamsungHealthStatus.notInstalled,
        'updateRequired' => SamsungHealthStatus.updateRequired,
        'disabled' => SamsungHealthStatus.disabled,
        'notInitialized' => SamsungHealthStatus.notInitialized,
        'unavailable' => SamsungHealthStatus.unavailable,
        'unsupported' => SamsungHealthStatus.unsupported,
        _ => SamsungHealthStatus.error,
      };
    } on PlatformException {
      return SamsungHealthStatus.error;
    } on MissingPluginException {
      return SamsungHealthStatus.unsupported;
    }
  }

  Future<SamsungHealthStatus> getStepTargetStatus() async {
    if (!Platform.isAndroid) return SamsungHealthStatus.unsupported;
    try {
      final value = await _channel.invokeMethod<String>(
        'samsungStepTargetStatus',
      );
      return _statusFromPlatform(value);
    } on PlatformException {
      return SamsungHealthStatus.error;
    } on MissingPluginException {
      return SamsungHealthStatus.unsupported;
    }
  }

  Future<bool> requestSleepTargetPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestSamsungSleepTargetPermission',
        ) ??
        false;
  }

  Future<SamsungSleepTarget?> readSleepTarget() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'readSamsungSleepTarget',
    );
    return value == null ? null : SamsungSleepTarget.fromPlatform(value);
  }

  Future<bool> requestStepTargetPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestSamsungStepTargetPermission',
        ) ??
        false;
  }

  Future<SamsungStepTarget?> readStepTarget() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'readSamsungStepTarget',
    );
    return value == null ? null : SamsungStepTarget.fromPlatform(value);
  }

  static SamsungHealthStatus _statusFromPlatform(String? value) {
    return switch (value) {
      'connected' => SamsungHealthStatus.connected,
      'permissionRequired' => SamsungHealthStatus.permissionRequired,
      'noTarget' => SamsungHealthStatus.noTarget,
      'authorizationRequired' => SamsungHealthStatus.authorizationRequired,
      'notInstalled' => SamsungHealthStatus.notInstalled,
      'updateRequired' => SamsungHealthStatus.updateRequired,
      'disabled' => SamsungHealthStatus.disabled,
      'notInitialized' => SamsungHealthStatus.notInitialized,
      'unavailable' => SamsungHealthStatus.unavailable,
      'unsupported' => SamsungHealthStatus.unsupported,
      _ => SamsungHealthStatus.error,
    };
  }
}

class HealthConnectService {
  const HealthConnectService();

  static const _channel = MethodChannel('com.med.move/device');

  Future<HealthConnectStatus> getStatus() async {
    if (!Platform.isAndroid) return HealthConnectStatus.unsupported;
    try {
      final value = await _channel.invokeMethod<String>('healthStatus');
      return switch (value) {
        'connected' => HealthConnectStatus.connected,
        'permissionRequired' => HealthConnectStatus.permissionRequired,
        'updateRequired' => HealthConnectStatus.updateRequired,
        'unsupported' => HealthConnectStatus.unsupported,
        _ => HealthConnectStatus.error,
      };
    } on PlatformException {
      return HealthConnectStatus.error;
    } on MissingPluginException {
      return HealthConnectStatus.unsupported;
    }
  }

  Future<bool> requestStepsPermission() async {
    return await _channel.invokeMethod<bool>('requestStepsPermission') ?? false;
  }

  Future<HealthConnectStatus> getSleepStatus() async {
    if (!Platform.isAndroid) return HealthConnectStatus.unsupported;
    try {
      final value = await _channel.invokeMethod<String>('sleepStatus');
      return switch (value) {
        'connected' => HealthConnectStatus.connected,
        'permissionRequired' => HealthConnectStatus.permissionRequired,
        'updateRequired' => HealthConnectStatus.updateRequired,
        'unsupported' => HealthConnectStatus.unsupported,
        _ => HealthConnectStatus.error,
      };
    } on PlatformException {
      return HealthConnectStatus.error;
    } on MissingPluginException {
      return HealthConnectStatus.unsupported;
    }
  }

  Future<bool> requestSleepPermission() async {
    return await _channel.invokeMethod<bool>('requestSleepPermission') ?? false;
  }

  Future<List<DailyStepCount>> readDailySteps({int days = 14}) async {
    final values = await _channel.invokeListMethod<Object?>('readDailySteps', {
      'days': days,
    });
    return (values ?? const [])
        .map(
          (value) =>
              DailyStepCount.fromPlatform(value! as Map<Object?, Object?>),
        )
        .toList();
  }

  Future<DailySleepSync> readDailySleep({int days = 14}) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'readDailySleep',
      {'days': days},
    );
    if (value == null) {
      throw StateError('Health Connect returned no sleep data.');
    }
    return DailySleepSync.fromPlatform(value);
  }

  Future<void> openSettings() => _channel.invokeMethod('openHealthConnect');
}

class DailySleepSync {
  const DailySleepSync({
    required this.startDate,
    required this.endDate,
    required this.records,
  });

  final DateTime startDate;
  final DateTime endDate;
  final List<DailySleepRecord> records;

  factory DailySleepSync.fromPlatform(Map<Object?, Object?> map) {
    DateTime parseDate(Object? value) {
      final parts = (value as String).split('-').map(int.parse).toList();
      return DateTime(parts[0], parts[1], parts[2]);
    }

    final rawRecords = map['records'];
    if (rawRecords is! List<Object?>) {
      throw const FormatException('Sleep sync records are missing.');
    }
    return DailySleepSync(
      startDate: parseDate(map['startDate']),
      endDate: parseDate(map['endDate']),
      records: rawRecords
          .map(
            (value) =>
                DailySleepRecord.fromPlatform(value! as Map<Object?, Object?>),
          )
          .toList(),
    );
  }
}

class SmartAlertStatus {
  const SmartAlertStatus({
    required this.enabled,
    required this.notificationGranted,
    required this.stepsGranted,
    required this.backgroundReadAvailable,
    required this.backgroundReadGranted,
    required this.operational,
    required this.workerScheduled,
    required this.active,
    required this.trackingStartAt,
    required this.activeWindowEndAt,
    required this.inactiveSince,
    required this.lastActivityAt,
    required this.lastAlertAt,
    required this.alertsToday,
    required this.nextCheckAt,
    required this.deferReason,
  });

  final bool enabled;
  final bool notificationGranted;
  final bool stepsGranted;
  final bool backgroundReadAvailable;
  final bool backgroundReadGranted;
  final bool operational;
  final bool workerScheduled;
  final bool active;
  final DateTime? trackingStartAt;
  final DateTime? activeWindowEndAt;
  final DateTime? inactiveSince;
  final DateTime? lastActivityAt;
  final DateTime? lastAlertAt;
  final int alertsToday;
  final DateTime? nextCheckAt;
  final String deferReason;

  bool get permissionsGranted =>
      notificationGranted &&
      stepsGranted &&
      backgroundReadAvailable &&
      backgroundReadGranted;

  bool get needsPermissionSetup => !permissionsGranted;

  factory SmartAlertStatus.fromPlatform(Map<Object?, Object?> map) {
    DateTime? parseTimestamp(String key) {
      final value = (map[key] as num?)?.toInt() ?? 0;
      return value > 0 ? DateTime.fromMillisecondsSinceEpoch(value) : null;
    }

    return SmartAlertStatus(
      enabled: map['enabled'] as bool? ?? false,
      notificationGranted: map['notificationGranted'] as bool? ?? false,
      stepsGranted: map['stepsGranted'] as bool? ?? false,
      backgroundReadAvailable: map['backgroundReadAvailable'] as bool? ?? false,
      backgroundReadGranted: map['backgroundReadGranted'] as bool? ?? false,
      operational: map['operational'] as bool? ?? false,
      workerScheduled: map['workerScheduled'] as bool? ?? false,
      active: map['active'] as bool? ?? false,
      trackingStartAt: parseTimestamp('trackingStartAt'),
      activeWindowEndAt: parseTimestamp('activeWindowEndAt'),
      inactiveSince: parseTimestamp('inactiveSince'),
      lastActivityAt: parseTimestamp('lastActivityAt'),
      lastAlertAt: parseTimestamp('lastAlertAt'),
      alertsToday: (map['alertsToday'] as num?)?.toInt() ?? 0,
      nextCheckAt: parseTimestamp('nextCheckAt'),
      deferReason: map['deferReason'] as String? ?? '',
    );
  }
}

class SmartAlertService {
  const SmartAlertService();

  static const _channel = MethodChannel('com.med.move/device');

  Future<SmartAlertStatus> getStatus() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'reminderStatus',
    );
    return SmartAlertStatus.fromPlatform(value ?? const {});
  }

  Future<bool> requestNotificationPermission() async {
    return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
  }

  Future<SmartAlertStatus> requestActivityPermissions() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'requestSmartAlertPermissions',
    );
    return SmartAlertStatus.fromPlatform(value ?? const {});
  }

  Future<SmartAlertStatus> setEnabled(bool enabled) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'setReminderEnabled',
      {'enabled': enabled},
    );
    return SmartAlertStatus.fromPlatform(value ?? const {});
  }

  Future<void> recordMovementActivity({required DateTime createdAt}) {
    return _channel.invokeMethod<void>('recordMovementActivity', {
      'createdAt': createdAt.millisecondsSinceEpoch,
    });
  }
}

@Deprecated('Use SmartAlertStatus.')
typedef ReminderStatus = SmartAlertStatus;

@Deprecated('Use SmartAlertService.')
class ReminderService extends SmartAlertService {
  const ReminderService();
}

class MovePreferences {
  const MovePreferences({
    required this.goals,
    required this.quickMovementIds,
    required this.cachedSamsungStepTarget,
  });

  final DailyGoalSettings goals;
  final List<String> quickMovementIds;
  final SamsungStepTarget? cachedSamsungStepTarget;

  factory MovePreferences.fromPlatform(Map<Object?, Object?> map) {
    final rawIds = (map['quickMovementIds'] as List<Object?>? ?? const [])
        .whereType<String>();
    final validIds = <String>[];
    for (final id in rawIds) {
      if (MovementCatalog.movements.any((movement) => movement.id == id) &&
          !validIds.contains(id)) {
        validIds.add(id);
      }
    }
    SamsungStepTarget? cachedSamsungStepTarget;
    try {
      if (map.containsKey('cachedSamsungStepGoal')) {
        cachedSamsungStepTarget = SamsungStepTarget.fromPlatform({
          'steps': map['cachedSamsungStepGoal'],
          'date': map['cachedSamsungStepGoalDate'],
        });
      }
    } on FormatException {
      cachedSamsungStepTarget = null;
    }
    return MovePreferences(
      goals: DailyGoalSettings.fromPlatform(map),
      quickMovementIds: validIds.length >= 2
          ? validIds.take(8).toList()
          : List.of(MovementCatalog.quickIds),
      cachedSamsungStepTarget: cachedSamsungStepTarget,
    );
  }
}

class MovePreferencesService {
  const MovePreferencesService();

  static const _channel = MethodChannel('com.med.move/device');

  Future<MovePreferences> getPreferences() async {
    if (!Platform.isAndroid) {
      return MovePreferences(
        goals: DailyGoalSettings.standard,
        quickMovementIds: List.of(MovementCatalog.quickIds),
        cachedSamsungStepTarget: null,
      );
    }
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'appPreferences',
    );
    return MovePreferences.fromPlatform(value ?? const {});
  }

  Future<DailyGoalSettings> setGoals(DailyGoalSettings goals) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'setDailyGoals',
      {'stepGoal': goals.stepGoal, 'movementGoal': goals.movementGoal},
    );
    return DailyGoalSettings.fromPlatform(value ?? const {});
  }

  Future<void> setQuickMovementIds(List<String> ids) {
    return _channel.invokeMethod<void>('setQuickMovementIds', {'ids': ids});
  }

  Future<void> updateSnapshot({
    required DateTime date,
    required int steps,
    required int movements,
    required int streak,
    required int stepGoal,
    required bool usesSamsungStepGoal,
  }) {
    return _channel.invokeMethod<void>('updateMoveSnapshot', {
      'date':
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      'steps': steps,
      'movements': movements,
      'streak': streak,
      'stepGoal': stepGoal,
      'usesSamsungStepGoal': usesSamsungStepGoal,
    });
  }
}

class HomeWidgetStatus {
  const HomeWidgetStatus({required this.supported, required this.active});

  final bool supported;
  final bool active;

  factory HomeWidgetStatus.fromPlatform(Map<Object?, Object?> map) {
    return HomeWidgetStatus(
      supported: map['supported'] as bool? ?? false,
      active: map['active'] as bool? ?? false,
    );
  }
}

class HomeWidgetService {
  const HomeWidgetService();

  static const _channel = MethodChannel('com.med.move/device');

  Future<HomeWidgetStatus> getStatus() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'homeWidgetStatus',
    );
    return HomeWidgetStatus.fromPlatform(value ?? const {});
  }

  Future<bool> requestPin() async {
    return await _channel.invokeMethod<bool>('pinHomeWidget') ?? false;
  }
}
