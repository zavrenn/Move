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
  final _smartAlerts = const SmartAlertService();
  final _preferences = const MovePreferencesService();
  final _widget = const HomeWidgetService();

  HealthConnectStatus? _healthStatus;
  HealthConnectStatus? _sleepStatus;
  SamsungHealthStatus? _stepTargetStatus;
  SamsungHealthStatus? _sleepTargetStatus;
  SamsungStepTarget? _stepTarget;
  SamsungSleepTarget? _sleepTarget;
  SmartAlertStatus? _smartAlertStatus;
  DailyGoalSettings _goals = DailyGoalSettings.standard;
  HomeWidgetStatus? _widgetStatus;
  bool _healthBusy = false;
  bool _sleepBusy = false;
  bool _stepTargetBusy = false;
  bool _sleepTargetBusy = false;
  bool _stepTargetFailed = false;
  bool _sleepTargetFailed = false;
  bool _smartAlertBusy = false;
  bool _goalBusy = false;
  bool _widgetBusy = false;

  SamsungStepTarget? get _currentStepTarget =>
      _stepTarget?.isForLocalDate(DateTime.now()) == true ? _stepTarget : null;

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
      _loadSmartAlertStatus();
      _refreshStepTarget();
      _refreshSleepTarget();
    }
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        _health.getStatus(),
        _health.getSleepStatus(),
        _smartAlerts.getStatus(),
        _preferences.getPreferences(),
        _widget.getStatus(),
      ]);
      if (!mounted) return;
      final preferences = values[3] as MovePreferences;
      setState(() {
        _healthStatus = values[0] as HealthConnectStatus;
        _sleepStatus = values[1] as HealthConnectStatus;
        _smartAlertStatus = values[2] as SmartAlertStatus;
        _goals = preferences.goals;
        _stepTarget = preferences.cachedSamsungStepTarget;
        if (_stepTarget != null) {
          _stepTargetStatus = SamsungHealthStatus.connected;
        }
        _widgetStatus = values[4] as HomeWidgetStatus;
      });
      await Future.wait([_refreshStepTarget(), _refreshSleepTarget()]);
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

  Future<void> _loadSmartAlertStatus() async {
    try {
      final status = await _smartAlerts.getStatus();
      if (mounted) setState(() => _smartAlertStatus = status);
    } catch (_) {
      // The status will refresh the next time settings opens.
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

  Future<void> _refreshStepTarget() async {
    if (_stepTargetBusy) return;
    if (mounted) {
      setState(() {
        _stepTargetBusy = true;
        _stepTargetFailed = false;
      });
    }
    try {
      final status = await _samsungHealth.getStepTargetStatus();
      if (!mounted) return;
      if (status == SamsungHealthStatus.error) {
        setState(() {
          _stepTargetStatus = status;
          _stepTargetFailed = true;
        });
        return;
      }
      setState(() {
        _stepTargetStatus = status;
        if (status != SamsungHealthStatus.connected) _stepTarget = null;
      });
      if (status != SamsungHealthStatus.connected) return;
      final target = await _samsungHealth.readStepTarget();
      if (!mounted) return;
      setState(() {
        _stepTarget = target;
        _stepTargetStatus = target == null
            ? SamsungHealthStatus.noTarget
            : SamsungHealthStatus.connected;
      });
    } catch (_) {
      final status = await _samsungHealth.getStepTargetStatus();
      if (!mounted) return;
      final targetIsCurrent =
          _stepTarget?.isForLocalDate(DateTime.now()) == true;
      final isTransient =
          status == SamsungHealthStatus.connected ||
          status == SamsungHealthStatus.error;
      setState(() {
        _stepTargetStatus = status;
        _stepTargetFailed = isTransient;
        if (!isTransient || !targetIsCurrent) _stepTarget = null;
      });
    } finally {
      if (mounted) setState(() => _stepTargetBusy = false);
    }
  }

  Future<void> _connectStepTarget() async {
    if (_stepTargetBusy) return;
    final wasPermissionRequest =
        _stepTargetStatus == SamsungHealthStatus.permissionRequired;
    setState(() => _stepTargetBusy = true);
    try {
      final granted = await _samsungHealth.requestStepTargetPermission();
      if (!granted && mounted && wasPermissionRequest) {
        _showError('Step target access was not enabled.');
      }
    } catch (_) {
      if (mounted) _showError('Step target access was not enabled.');
    } finally {
      if (mounted) setState(() => _stepTargetBusy = false);
    }
    await _refreshStepTarget();
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

  Future<void> _toggleSmartAlerts(bool enabled) async {
    if (_smartAlertBusy) return;
    if (!enabled) {
      setState(() => _smartAlertBusy = true);
      try {
        final status = await _smartAlerts.setEnabled(false);
        if (mounted) setState(() => _smartAlertStatus = status);
      } catch (_) {
        if (mounted) _showError('Could not turn off movement alerts.');
      } finally {
        if (mounted) setState(() => _smartAlertBusy = false);
      }
      return;
    }
    await _configureSmartAlerts(enableWhenReady: true);
  }

  Future<void> _configureSmartAlerts({bool enableWhenReady = false}) async {
    if (_smartAlertBusy) return;
    setState(() => _smartAlertBusy = true);
    try {
      var status = _smartAlertStatus ?? await _smartAlerts.getStatus();
      final shouldEnable = enableWhenReady || status.enabled;

      if (!status.notificationGranted) {
        await _smartAlerts.requestNotificationPermission();
        status = await _smartAlerts.getStatus();
        if (!status.notificationGranted) {
          if (mounted) {
            setState(() => _smartAlertStatus = status);
            _showError(_missingSmartAlertPermission(status));
          }
          return;
        }
      }
      if (!status.backgroundReadAvailable) {
        if (mounted) {
          setState(() => _smartAlertStatus = status);
          _showError(
            'Smart Alerts require Android 14+ and compatible Health Connect '
            'background access.',
          );
        }
        return;
      }
      if (!status.stepsGranted || !status.backgroundReadGranted) {
        status = await _smartAlerts.requestActivityPermissions();
      }
      if (!mounted) return;
      setState(() => _smartAlertStatus = status);
      if (!status.permissionsGranted) {
        _showError(_missingSmartAlertPermission(status));
        return;
      }
      if (shouldEnable) {
        status = await _smartAlerts.setEnabled(true);
        if (mounted) setState(() => _smartAlertStatus = status);
      }
    } catch (_) {
      await _loadSmartAlertStatus();
      if (mounted) _showError('Could not finish movement alert setup.');
    } finally {
      if (mounted) setState(() => _smartAlertBusy = false);
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
    final smartAlert = _smartAlertStatus;
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
                  title: 'Smart movement alerts',
                  subtitle: 'Adaptive nudges after an inactive hour',
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: smartAlert?.enabled ?? false,
                        onChanged:
                            smartAlert == null ||
                                _smartAlertBusy ||
                                (!smartAlert.enabled &&
                                    !smartAlert.backgroundReadAvailable)
                            ? null
                            : _toggleSmartAlerts,
                        secondary: const Icon(
                          Icons.notifications_active_rounded,
                          color: MoveColors.primary,
                        ),
                        title: const Text('Adaptive inactivity alerts'),
                        subtitle: Text(_smartAlertDescription(smartAlert)),
                      ),
                      if (smartAlert?.needsPermissionSetup == true &&
                          smartAlert?.backgroundReadAvailable == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 44),
                          child: TextButton.icon(
                            onPressed: _smartAlertBusy
                                ? null
                                : () => _configureSmartAlerts(),
                            icon: const Icon(Icons.security_rounded),
                            label: const Text('Finish setup'),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(44, 0, 8, 4),
                        child: Text(
                          'While enabled, Move reads steps in the background. '
                          'Health data stays read-only and on this device.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle(
                  title: 'Daily goals',
                  subtitle: 'Active targets with a configurable Move fallback',
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
                      if (_currentStepTarget != null) ...[
                        const Divider(height: 1),
                        _GoalSettingRow(
                          icon: Icons.directions_walk_rounded,
                          color: MoveColors.secondary,
                          label: 'Daily steps',
                          detail: 'Samsung Health · active',
                          value: NumberFormat.decimalPattern().format(
                            _currentStepTarget!.steps,
                          ),
                          showControls: false,
                          onDecrease: null,
                          onIncrease: null,
                        ),
                      ],
                      const Divider(height: 1),
                      _GoalSettingRow(
                        icon: Icons.shield_outlined,
                        color: MoveColors.secondary,
                        label: 'Move fallback',
                        detail: _currentStepTarget == null
                            ? 'Active'
                            : 'Backup',
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
                  subtitle: 'Totals from Health Connect · target from Samsung',
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
                              color: MoveColors.secondary.withValues(
                                alpha: 0.12,
                              ),
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
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
                                    onPressed: _healthBusy
                                        ? null
                                        : _connectSteps,
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
                      const Divider(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.track_changes_rounded,
                              color: MoveColors.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Step target · Samsung Health',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _stepTargetDescription(),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_currentStepTarget != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Target ${NumberFormat.decimalPattern().format(_currentStepTarget!.steps)} steps',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (_canConnectStepTarget)
                                  FilledButton.tonalIcon(
                                    onPressed: _stepTargetBusy
                                        ? null
                                        : _connectStepTarget,
                                    icon: const Icon(Icons.link_rounded),
                                    label: Text(_stepTargetActionLabel),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: _stepTargetBusy
                                        ? null
                                        : _refreshStepTarget,
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
                  'plus your step and sleep targets from Samsung Health. It never writes '
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

  String _smartAlertDescription(SmartAlertStatus? status) {
    if (status == null) return 'Checking setup…';
    if (!status.backgroundReadAvailable) {
      return 'Requires Android 14+ and compatible Health Connect background access.';
    }
    if (!status.notificationGranted) {
      return status.enabled
          ? 'Paused · notification access is required.'
          : 'Setup requires notification access.';
    }
    if (!status.stepsGranted) {
      return status.enabled
          ? 'Paused · Health Connect steps access is required.'
          : 'Setup requires Health Connect steps access.';
    }
    if (!status.backgroundReadGranted) {
      return status.enabled
          ? 'Paused · background activity access is required.'
          : 'Setup requires background activity access.';
    }
    if (!status.enabled) {
      return 'Alerts after 60 inactive minutes · quiet during sleep and after goals.';
    }
    if (!status.operational || !status.workerScheduled) {
      return 'Enabled · waiting for background monitoring.';
    }

    final deferred = switch (status.deferReason) {
      'outside_active_window' => 'Quiet during sleep hours.',
      'goals_complete' => 'Quiet · today’s activity goals are complete.',
      'unreliable_steps' => 'Paused until step data is reliable.',
      'unreliable_target' => 'Paused until the daily step target is reliable.',
      'step_counter_reset' =>
        'Step data changed · rebuilding the inactivity baseline.',
      'awaiting_baseline' => 'Establishing the current activity baseline.',
      'activity_detected' => 'Activity detected · inactivity timer restarted.',
      'cooldown' => 'Cooling down after the last alert.',
      'daily_limit' => 'Quiet · today’s three-alert limit is reached.',
      'notification_visible' => 'An alert is already waiting for you.',
      _ => null,
    };
    if (deferred != null) return deferred;

    final trackingStart = status.trackingStartAt;
    if (trackingStart != null && DateTime.now().isBefore(trackingStart)) {
      final earliestAlert = trackingStart.add(const Duration(hours: 1));
      return 'Tracking starts ${DateFormat.jm().format(trackingStart)} · '
          'earliest alert ${DateFormat.jm().format(earliestAlert)}.';
    }
    final used = status.alertsToday.clamp(0, 3);
    return status.active
        ? 'Monitoring activity · $used of 3 alerts used today.'
        : 'Enabled · quiet until the next active window.';
  }

  String _missingSmartAlertPermission(SmartAlertStatus status) {
    if (!status.notificationGranted) {
      return 'Notification access is required for movement alerts.';
    }
    if (!status.stepsGranted) {
      return 'Health Connect steps access is required for movement alerts.';
    }
    if (!status.backgroundReadAvailable) {
      return 'Smart Alerts require Android 14+ and compatible Health Connect '
          'background access.';
    }
    if (!status.backgroundReadGranted) {
      return 'Background activity access is required for movement alerts.';
    }
    return 'Movement alert setup is incomplete.';
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

  String _stepTargetDescription() {
    final fallback = NumberFormat.decimalPattern().format(_goals.stepGoal);
    if (_stepTargetBusy) return 'Checking Samsung Health…';
    if (_stepTargetFailed) {
      return _currentStepTarget == null
          ? 'Refresh failed; using the $fallback-step Move fallback.'
          : 'Refresh failed; still using the last Samsung Health target.';
    }
    return switch (_stepTargetStatus) {
      null => 'Checking availability and permission status.',
      SamsungHealthStatus.connected =>
        'Read-only target used for scoring, progress, and reminders.',
      SamsungHealthStatus.permissionRequired =>
        'Connect the target; until then Move uses the $fallback-step fallback.',
      SamsungHealthStatus.noTarget =>
        'No Samsung target found; using the $fallback-step Move fallback.',
      SamsungHealthStatus.authorizationRequired =>
        'Samsung Health did not authorize this build; using the Move fallback.',
      SamsungHealthStatus.notInstalled =>
        'Samsung Health is not installed; using the Move fallback.',
      SamsungHealthStatus.updateRequired =>
        'Update Samsung Health; until then Move uses its fallback.',
      SamsungHealthStatus.disabled =>
        'Samsung Health is disabled; using the Move fallback.',
      SamsungHealthStatus.notInitialized =>
        'Finish setting up Samsung Health; using the Move fallback for now.',
      SamsungHealthStatus.unavailable =>
        'Samsung Health is unavailable; using the Move fallback.',
      SamsungHealthStatus.unsupported =>
        'Samsung step targets are unsupported; using the Move fallback.',
      SamsungHealthStatus.error =>
        'Could not check the Samsung target; using the Move fallback.',
    };
  }

  bool get _canConnectStepTarget => switch (_stepTargetStatus) {
    SamsungHealthStatus.permissionRequired ||
    SamsungHealthStatus.notInstalled ||
    SamsungHealthStatus.updateRequired ||
    SamsungHealthStatus.disabled ||
    SamsungHealthStatus.notInitialized ||
    SamsungHealthStatus.unavailable => true,
    _ => false,
  };

  String get _stepTargetActionLabel => switch (_stepTargetStatus) {
    SamsungHealthStatus.permissionRequired => 'Connect target',
    SamsungHealthStatus.notInstalled => 'Install Samsung Health',
    SamsungHealthStatus.updateRequired => 'Update Samsung Health',
    SamsungHealthStatus.disabled => 'Enable Samsung Health',
    SamsungHealthStatus.notInitialized => 'Open Samsung Health',
    _ => 'Fix Samsung Health',
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
    this.detail,
    this.showControls = true,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? detail;
  final bool showControls;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                if (detail != null)
                  Text(detail!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (showControls) ...[
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
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
