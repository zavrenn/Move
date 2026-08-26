import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'device_services.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

Future<void> showMoveSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => const FractionallySizedBox(
      heightFactor: 0.82,
      child: _MoveSettingsSheet(),
    ),
  );
}

class _MoveSettingsSheet extends StatefulWidget {
  const _MoveSettingsSheet();

  @override
  State<_MoveSettingsSheet> createState() => _MoveSettingsSheetState();
}

class _MoveSettingsSheetState extends State<_MoveSettingsSheet> {
  final _health = const HealthConnectService();
  final _reminders = const ReminderService();

  HealthConnectStatus? _healthStatus;
  ReminderStatus? _reminderStatus;
  bool _healthBusy = false;
  bool _reminderBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        _health.getStatus(),
        _reminders.getStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _healthStatus = values[0] as HealthConnectStatus;
        _reminderStatus = values[1] as ReminderStatus;
      });
    } catch (_) {
      if (!mounted) return;
      _showError('Could not load settings.');
    }
  }

  Future<void> _connectSteps() async {
    setState(() => _healthBusy = true);
    try {
      await _health.requestStepsPermission();
      final status = await _health.getStatus();
      if (!mounted) return;
      setState(() => _healthStatus = status);
    } catch (_) {
      if (mounted) _showError('Steps access was not enabled.');
    } finally {
      if (mounted) setState(() => _healthBusy = false);
    }
  }

  Future<void> _toggleReminder(bool enabled) async {
    setState(() => _reminderBusy = true);
    try {
      var granted = _reminderStatus?.notificationGranted ?? false;
      if (enabled && !granted) {
        granted = await _reminders.requestPermission();
      }
      if (enabled && !granted) {
        if (mounted) _showError('Notification permission was not enabled.');
        return;
      }
      final status = await _reminders.setEnabled(enabled);
      if (!mounted) return;
      setState(() => _reminderStatus = status);
    } catch (_) {
      if (mounted) _showError('Could not update the daily reminder.');
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reminder = _reminderStatus;
    return Container(
      decoration: const BoxDecoration(
        color: MoveColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: MoveColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: MoveColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Move settings',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionTitle(
                  title: 'Daily reminder',
                  subtitle: 'A gentle nudge—not a rigid schedule',
                ),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: reminder?.enabled ?? false,
                    onChanged: reminder == null || _reminderBusy
                        ? null
                        : _toggleReminder,
                    secondary: const Icon(
                      Icons.notifications_active_rounded,
                      color: MoveColors.primary,
                    ),
                    title: const Text('Remind me to move'),
                    subtitle: Text(_reminderDescription(reminder)),
                  ),
                ),
                const SizedBox(height: 26),
                const SectionTitle(
                  title: 'Walking & steps',
                  subtitle: 'Read-only through Health Connect',
                ),
                const SizedBox(height: 12),
                SurfaceCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: MoveColors.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.directions_walk_rounded,
                          color: MoveColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _healthTitle(_healthStatus),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _healthDescription(_healthStatus),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 14),
                            if (_healthStatus ==
                                HealthConnectStatus.permissionRequired)
                              FilledButton.tonalIcon(
                                onPressed: _healthBusy ? null : _connectSteps,
                                icon: const Icon(Icons.link_rounded),
                                label: const Text('Connect steps'),
                              )
                            else if (_healthStatus ==
                                HealthConnectStatus.connected)
                              TextButton.icon(
                                onPressed: _health.openSettings,
                                icon: const Icon(Icons.tune_rounded),
                                label: const Text('Manage access'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Move reads only daily step totals. It never writes health '
                  'data, and everything remains on this device.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _reminderDescription(ReminderStatus? status) {
    if (status == null) return 'Loading…';
    if (!status.enabled) return 'One random reminder between 5 AM and 11 PM';
    final next = status.nextAt;
    if (next == null) return 'One random reminder between 5 AM and 11 PM';
    return 'Next reminder ${DateFormat('EEE · h:mm a').format(next)}';
  }

  String _healthTitle(HealthConnectStatus? status) => switch (status) {
    null => 'Checking Health Connect…',
    HealthConnectStatus.connected => 'Steps connected',
    HealthConnectStatus.permissionRequired => 'Connect your steps',
    HealthConnectStatus.updateRequired => 'Health Connect needs an update',
    HealthConnectStatus.unsupported => 'Health Connect unavailable',
    HealthConnectStatus.error => 'Could not check steps access',
  };

  String _healthDescription(HealthConnectStatus? status) => switch (status) {
    HealthConnectStatus.connected =>
      'Move refreshes your daily totals when the app opens.',
    HealthConnectStatus.permissionRequired =>
      'Allow Move to read steps recorded by Samsung Health.',
    HealthConnectStatus.updateRequired =>
      'Update Health Connect before linking daily steps.',
    HealthConnectStatus.unsupported =>
      'This device does not currently support Health Connect.',
    HealthConnectStatus.error => 'Try again after reopening Move.',
    null => 'Checking availability and permission status.',
  };
}
