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

class ReminderStatus {
  const ReminderStatus({
    required this.enabled,
    required this.notificationGranted,
    required this.nextAt,
    required this.startHour,
    required this.endHour,
  });

  final bool enabled;
  final bool notificationGranted;
  final DateTime? nextAt;
  final int startHour;
  final int endHour;

  factory ReminderStatus.fromPlatform(Map<Object?, Object?> map) {
    final nextAt = (map['nextAt'] as num?)?.toInt() ?? 0;
    return ReminderStatus(
      enabled: map['enabled'] as bool? ?? false,
      notificationGranted: map['notificationGranted'] as bool? ?? false,
      nextAt: nextAt > 0 ? DateTime.fromMillisecondsSinceEpoch(nextAt) : null,
      startHour: (map['startHour'] as num?)?.toInt() ?? 5,
      endHour: (map['endHour'] as num?)?.toInt() ?? 23,
    );
  }
}

class ReminderService {
  const ReminderService();

  static const _channel = MethodChannel('com.med.move/device');

  Future<ReminderStatus> getStatus() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'reminderStatus',
    );
    return ReminderStatus.fromPlatform(value ?? const {});
  }

  Future<bool> requestPermission() async {
    return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
  }

  Future<ReminderStatus> setEnabled(bool enabled) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'setReminderEnabled',
      {'enabled': enabled},
    );
    return ReminderStatus.fromPlatform(value ?? const {});
  }
}

class MovePreferences {
  const MovePreferences({required this.goals, required this.quickMovementIds});

  final DailyGoalSettings goals;
  final List<String> quickMovementIds;

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
    return MovePreferences(
      goals: DailyGoalSettings.fromPlatform(map),
      quickMovementIds: validIds.length >= 2
          ? validIds.take(8).toList()
          : List.of(MovementCatalog.quickIds),
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
  }) {
    return _channel.invokeMethod<void>('updateMoveSnapshot', {
      'date':
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      'steps': steps,
      'movements': movements,
      'streak': streak,
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
