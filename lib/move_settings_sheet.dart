import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'device_services.dart';
import 'models.dart';
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

class _MoveSettingsSheetState extends State<_MoveSettingsSheet>
    with WidgetsBindingObserver {
  final _health = const HealthConnectService();
  final _samsungHealth = const SamsungHealthService();
  final _reminders = const ReminderService();
  final _preferences = const MovePreferencesService();
  final _widget = const HomeWidgetService();

  HealthConnectStatus? _healthStatus;
  HealthConnectStatus? _sleepStatus;
  SamsungHealthStatus? _sleepTargetStatus;
  SamsungSleepTarget? _sleepTarget;
  ReminderStatus? _reminderStatus;
  DailyGoalSettings _goals = DailyGoalSettings.standard;
  HomeWidgetStatus? _widgetStatus;
  bool _healthBusy = false;
  bool _sleepBusy = false;
  bool _sleepTargetBusy = false;
  bool _sleepTargetFailed = false;
  bool _reminderBusy = false;
  bool _goalBusy = false;
  bool _widgetBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadWidgetStatus();
      _refreshSleepTarget();
    }
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        _health.getStatus(),
        _health.getSleepStatus(),
        _reminders.getStatus(),
        _preferences.getPreferences(),
        _widget.getStatus(),
      ]);
      if (!mounted) return;
      final preferences = values[3] as MovePreferences;
      setState(() {
        _healthStatus = values[0] as HealthConnectStatus;
        _sleepStatus = values[1] as HealthConnectStatus;
        _reminderStatus = values[2] as ReminderStatus;
        _goals = preferences.goals;
        _widgetStatus = values[4] as HomeWidgetStatus;
      });
      await _refreshSleepTarget();
    } catch (_) {
      if (!mounted) return;
      _showError('Could not load settings.');
    }
  }

  Future<void> _loadWidgetStatus() async {
    try {
      final status = await _widget.getStatus();
      if (mounted) setState(() => _widgetStatus = status);
    } catch (_) {
      // The widget status will refresh the next time settings opens.
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

  Future<void> _connectSleep() async {
    setState(() => _sleepBusy = true);
    try {
      await _health.requestSleepPermission();
      final status = await _health.getSleepStatus();
      if (!mounted) return;
      setState(() => _sleepStatus = status);
    } catch (_) {
      if (mounted) _showError('Sleep access was not enabled.');
    } finally {
      if (mounted) setState(() => _sleepBusy = false);
    }
  }

  Future<void> _refreshSleepTarget() async {
    if (_sleepTargetBusy) return;
    if (mounted) {
      setState(() {
        _sleepTargetBusy = true;
        _sleepTargetFailed = false;
        _sleepTarget = null;
      });
    }
    try {
      final status = await _samsungHealth.getSleepTargetStatus();
      if (!mounted) return;
      setState(() => _sleepTargetStatus = status);
      if (status != SamsungHealthStatus.connected) return;
      final target = await _samsungHealth.readSleepTarget();
      if (!mounted) return;
      setState(() {
        _sleepTarget = target;
        _sleepTargetStatus = target == null
            ? SamsungHealthStatus.noTarget
            : SamsungHealthStatus.connected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sleepTarget = null;
        _sleepTargetFailed = true;
      });
    } finally {
      if (mounted) setState(() => _sleepTargetBusy = false);
    }
  }

  Future<void> _connectSleepTarget() async {
    if (_sleepTargetBusy) return;
    final wasPermissionRequest =
        _sleepTargetStatus == SamsungHealthStatus.permissionRequired;
    setState(() => _sleepTargetBusy = true);
    try {
      final granted = await _samsungHealth.requestSleepTargetPermission();
      if (!granted && mounted && wasPermissionRequest) {
        _showError('Sleep target access was not enabled.');
      }
    } catch (_) {
      if (mounted) _showError('Sleep target access was not enabled.');
    } finally {
      if (mounted) setState(() => _sleepTargetBusy = false);
    }
    await _refreshSleepTarget();
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

  Future<void> _setGoals(DailyGoalSettings next) async {
    if (_goalBusy) return;
    final previous = _goals;
    setState(() {
      _goalBusy = true;
      _goals = next;
    });
    try {
      final saved = await _preferences.setGoals(next);
      if (mounted) setState(() => _goals = saved);
    } catch (_) {
      if (mounted) {
        setState(() => _goals = previous);
        _showError('Could not update daily goals.');
      }
    } finally {
      if (mounted) setState(() => _goalBusy = false);
    }
  }

  Future<void> _pinWidget() async {
    if (_widgetBusy) return;
    setState(() => _widgetBusy = true);
    try {
      final opened = await _widget.requestPin();
      if (!mounted) return;
      if (!opened) _showError('Add the Move widget from your widget picker.');
    } catch (_) {
      if (mounted) _showError('Could not open the widget picker.');
    } finally {
      if (mounted) setState(() => _widgetBusy = false);
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
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
                const SizedBox(height: 18),
                const SectionTitle(
                  title: 'Daily reminder',
                  subtitle: 'Adapts to progress and stays quiet when done',
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Daily goals',
                  subtitle: 'Flexible targets for movement and walking',
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      _GoalSettingRow(
                        icon: Icons.task_alt_rounded,
                        color: MoveColors.primary,
                        label: 'Movement sets',
                        value: '${_goals.movementGoal}',
                        onDecrease: !_goalBusy && _goals.movementGoal > 1
                            ? () => _setGoals(
                                _goals.copyWith(
                                  movementGoal: _goals.movementGoal - 1,
                                ),
                              )
                            : null,
                        onIncrease: !_goalBusy && _goals.movementGoal < 10
                            ? () => _setGoals(
                                _goals.copyWith(
                                  movementGoal: _goals.movementGoal + 1,
                                ),
                              )
                            : null,
                      ),
                      const Divider(height: 1),
                      _GoalSettingRow(
                        icon: Icons.directions_walk_rounded,
                        color: MoveColors.secondary,
                        label: 'Daily steps',
                        value: NumberFormat.decimalPattern().format(
                          _goals.stepGoal,
                        ),
                        onDecrease: !_goalBusy && _goals.stepGoal > 1000
                            ? () => _setGoals(
                                _goals.copyWith(
                                  stepGoal: _goals.stepGoal - 1000,
                                ),
                              )
                            : null,
                        onIncrease: !_goalBusy && _goals.stepGoal < 30000
                            ? () => _setGoals(
                                _goals.copyWith(
                                  stepGoal: _goals.stepGoal + 1000,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Sleep rhythm',
                  subtitle:
                      'Consistency matters; duration does not affect points',
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: MoveColors.sleep.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.bedtime_rounded,
                              color: MoveColors.sleep,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sleep sessions · Health Connect',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _sleepDescription(_sleepStatus),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                if (_sleepStatus ==
                                    HealthConnectStatus.permissionRequired)
                                  FilledButton.tonalIcon(
                                    onPressed: _sleepBusy
                                        ? null
                                        : _connectSleep,
                                    icon: const Icon(Icons.link_rounded),
                                    label: const Text('Connect sessions'),
                                  )
                                else if (_sleepStatus ==
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
                      const Divider(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.track_changes_rounded,
                              color: MoveColors.sleep,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sleep target · Samsung Health',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _sleepTargetDescription(),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_sleepTarget != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Target ${_timeLabel(_sleepTarget!.bedtimeMinutes)} · '
                                    'wake ${_timeLabel(_sleepTarget!.wakeMinutes)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Bedtime ${_timeRangeLabel(_sleepTarget!.bedtimeStartMinutes, _sleepTarget!.bedtimeEndMinutes)} · '
                                    'wake ${_timeRangeLabel(_sleepTarget!.wakeStartMinutes, _sleepTarget!.wakeEndMinutes)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (_canConnectSleepTarget)
                                  FilledButton.tonalIcon(
                                    onPressed: _sleepTargetBusy
                                        ? null
                                        : _connectSleepTarget,
                                    icon: const Icon(Icons.link_rounded),
                                    label: Text(_sleepTargetActionLabel),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: _sleepTargetBusy
                                        ? null
                                        : _refreshSleepTarget,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Refresh target'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Walking & steps',
                  subtitle: 'Read-only through Health Connect',
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: MoveColors.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.directions_walk_rounded,
                          color: MoveColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                            const SizedBox(height: 10),
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
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Home-screen widget',
                  subtitle: 'Your daily goals at a glance',
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: MoveColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.widgets_rounded,
                          color: MoveColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _widgetStatus?.active == true
                                  ? 'Widget active'
                                  : 'Add Move to Home',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Shows today’s steps, sets, and targets.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_widgetStatus?.supported == true)
                        IconButton.filledTonal(
                          onPressed: _widgetBusy ? null : _pinWidget,
                          tooltip: _widgetStatus?.active == true
                              ? 'Add another widget'
                              : 'Add widget',
                          icon: const Icon(Icons.add_rounded),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Move reads steps and sleep sessions from Health Connect, '
                  'plus your sleep target from Samsung Health. It never writes '
                  'health data, and everything remains on this device.',
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

  String _sleepDescription(HealthConnectStatus? status) => switch (status) {
    HealthConnectStatus.connected =>
      'Move reads your main sleep start and wake time.',
    HealthConnectStatus.permissionRequired =>
      'Allow read-only access to sleep sessions.',
    HealthConnectStatus.updateRequired =>
      'Update Health Connect before linking sleep timing.',
    HealthConnectStatus.unsupported =>
      'This device does not currently support Health Connect sleep.',
    HealthConnectStatus.error => 'Try again after reopening Move.',
    null => 'Checking availability and permission status.',
  };

  String _sleepTargetDescription() {
    if (_sleepTargetBusy) return 'Checking Samsung Health…';
    if (_sleepTargetFailed) return 'Target refresh failed. Try again.';
    return switch (_sleepTargetStatus) {
      null => 'Checking availability and permission status.',
      SamsungHealthStatus.connected =>
        'Read-only target; Move derives fixed ±30-minute windows.',
      SamsungHealthStatus.permissionRequired =>
        'Allow read-only access to your sleep target.',
      SamsungHealthStatus.noTarget =>
        'No sleep target found. Set it in Samsung Health, then refresh.',
      SamsungHealthStatus.authorizationRequired =>
        'Samsung Health did not authorize this build. Enable Developer Mode for local testing.',
      SamsungHealthStatus.notInstalled => 'Samsung Health is not installed.',
      SamsungHealthStatus.updateRequired =>
        'Update Samsung Health before reading the sleep target.',
      SamsungHealthStatus.disabled => 'Samsung Health is disabled.',
      SamsungHealthStatus.notInitialized =>
        'Finish setting up Samsung Health before reading the target.',
      SamsungHealthStatus.unavailable =>
        'Samsung Health is unavailable, disabled, or needs an update.',
      SamsungHealthStatus.unsupported =>
        'Samsung Health sleep targets are unsupported on this device.',
      SamsungHealthStatus.error => 'Could not check sleep target access.',
    };
  }

  bool get _canConnectSleepTarget => switch (_sleepTargetStatus) {
    SamsungHealthStatus.permissionRequired ||
    SamsungHealthStatus.notInstalled ||
    SamsungHealthStatus.updateRequired ||
    SamsungHealthStatus.disabled ||
    SamsungHealthStatus.notInitialized ||
    SamsungHealthStatus.unavailable => true,
    _ => false,
  };

  String get _sleepTargetActionLabel => switch (_sleepTargetStatus) {
    SamsungHealthStatus.permissionRequired => 'Connect target',
    SamsungHealthStatus.notInstalled => 'Install Samsung Health',
    SamsungHealthStatus.updateRequired => 'Update Samsung Health',
    SamsungHealthStatus.disabled => 'Enable Samsung Health',
    SamsungHealthStatus.notInitialized => 'Open Samsung Health',
    _ => 'Fix Samsung Health',
  };

  TimeOfDay _timeOfDay(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  String _timeLabel(int minutes) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      _timeOfDay(minutes),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  String _timeRangeLabel(int startMinutes, int endMinutes) {
    final localizations = MaterialLocalizations.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final start = localizations.formatTimeOfDay(
      _timeOfDay(startMinutes),
      alwaysUse24HourFormat: use24Hour,
    );
    final end = localizations.formatTimeOfDay(
      _timeOfDay(endMinutes),
      alwaysUse24HourFormat: use24Hour,
    );
    return '$start – $end';
  }
}

class _GoalSettingRow extends StatelessWidget {
  const _GoalSettingRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          IconButton(
            onPressed: onDecrease,
            tooltip: 'Decrease $label',
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 58,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onIncrease,
            tooltip: 'Increase $label',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
