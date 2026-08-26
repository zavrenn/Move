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

  Future<void> openSettings() => _channel.invokeMethod('openHealthConnect');
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
