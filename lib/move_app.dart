import 'dart:async';

import 'package:flutter/material.dart';

import 'analytics.dart';
import 'dashboard_screen.dart';
import 'device_services.dart';
import 'history_screen.dart';
import 'models.dart';
import 'move_database.dart';
import 'move_settings_sheet.dart';
import 'move_theme.dart';
import 'movement_log_sheet.dart';
import 'progress_screen.dart';
import 'quick_moves_sheet.dart';

class MoveApp extends StatelessWidget {
  const MoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Move',
      debugShowCheckedModeBanner: false,
      theme: MoveTheme.dark,
      darkTheme: MoveTheme.dark,
      themeMode: ThemeMode.dark,
      home: const MoveShell(),
    );
  }
}

class MoveShell extends StatefulWidget {
  const MoveShell({super.key});

  @override
  State<MoveShell> createState() => _MoveShellState();
}

class _MoveShellState extends State<MoveShell> with WidgetsBindingObserver {
  final _database = MoveDatabase.instance;
  final _health = const HealthConnectService();
  final _samsungHealth = const SamsungHealthService();
  final _preferences = const MovePreferencesService();
  List<MovementLog> _logs = const [];
  List<DailyStepCount> _steps = const [];
  List<DailySleepRecord> _sleep = const [];
  DailyGoalSettings _goals = DailyGoalSettings.standard;
  SamsungStepTarget? _stepTarget;
  SamsungSleepTarget? _sleepTarget;
  List<String> _quickMovementIds = List.of(MovementCatalog.quickIds);
  HealthConnectStatus? _healthStatus;
  HealthConnectStatus? _sleepStatus;
  SamsungHealthStatus? _sleepTargetStatus;
  bool _syncingSteps = false;
  bool _syncingSleep = false;
  bool _syncingSleepTarget = false;
  bool _requestingSleepTarget = false;
  bool _stepSyncFailed = false;
  bool _sleepSyncFailed = false;
  bool _sleepTargetSyncFailed = false;
  Future<void>? _stepTargetRefresh;
  Future<void>? _sleepTargetRefresh;
  bool _loading = true;
  String? _loadError;
  int _tab = 0;

  DailyGoalSettings get _effectiveGoals =>
      _goals.resolveStepTarget(_stepTarget);

  bool get _usesCurrentSamsungStepTarget =>
      _stepTarget?.isForLocalDate(DateTime.now()) == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      unawaited(_refreshHealthData());
    }
  }

  Future<void> _loadInitialData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait<Object>([
        _database.getAllLogs(),
        _database.getDailySteps(),
        _database.getDailySleep(),
        _preferences.getPreferences(),
      ]);
      if (!mounted) return;
      final preferences = values[3] as MovePreferences;
      setState(() {
        _logs = values[0] as List<MovementLog>;
        _steps = values[1] as List<DailyStepCount>;
        _sleep = values[2] as List<DailySleepRecord>;
        _goals = preferences.goals;
        _stepTarget = preferences.cachedSamsungStepTarget;
        _quickMovementIds = preferences.quickMovementIds;
        _loading = false;
        _loadError = null;
      });
      await _publishSnapshot();
      unawaited(_refreshHealthData());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _loadLogs() async {
    try {
      final logs = await _database.getAllLogs();
      if (!mounted) return;
      setState(() => _logs = logs);
      await _publishSnapshot();
    } catch (error) {
      if (!mounted) return;
      rethrow;
    }
  }

  Future<void> _refreshSteps() async {
    if (_syncingSteps) return;
    if (mounted) {
      setState(() {
        _syncingSteps = true;
        _stepSyncFailed = false;
      });
    }
    try {
      final status = await _health.getStatus();
      if (!mounted) return;
      setState(() {
        _healthStatus = status;
        _stepSyncFailed = status == HealthConnectStatus.error;
      });
      if (status != HealthConnectStatus.connected) return;

      final values = await _health.readDailySteps();
      await _database.upsertDailySteps(values);
      final cached = await _database.getDailySteps();
      if (!mounted) return;
      setState(() => _steps = cached);
    } catch (_) {
      if (mounted) setState(() => _stepSyncFailed = true);
    } finally {
      if (mounted) {
        setState(() => _syncingSteps = false);
        await _publishSnapshot();
      }
    }
  }

  Future<void> _refreshSleep() async {
    if (_syncingSleep) return;
    if (mounted) {
      setState(() {
        _syncingSleep = true;
        _sleepSyncFailed = false;
      });
    }
    try {
      final status = await _health.getSleepStatus();
      if (!mounted) return;
      setState(() {
        _sleepStatus = status;
        _sleepSyncFailed = status == HealthConnectStatus.error;
      });
      if (status != HealthConnectStatus.connected) return;

      final sync = await _health.readDailySleep(days: 14);
      await _database.replaceDailySleepRange(
        startDate: sync.startDate,
        endDate: sync.endDate,
        values: sync.records,
      );
      final cached = await _database.getDailySleep();
      if (!mounted) return;
      setState(() => _sleep = cached);
    } catch (_) {
      final status = await _health.getSleepStatus();
      if (!mounted) return;
      setState(() {
        _sleepStatus = status;
        _sleepSyncFailed =
            status == HealthConnectStatus.connected ||
            status == HealthConnectStatus.error;
      });
    } finally {
      if (mounted) setState(() => _syncingSleep = false);
    }
  }

  Future<void> _refreshStepTarget({bool refreshAgainIfBusy = false}) async {
    final activeRefresh = _stepTargetRefresh;
    if (activeRefresh != null) {
      await activeRefresh;
      if (!refreshAgainIfBusy) return;
    }

    final refresh = _performStepTargetRefresh();
    _stepTargetRefresh = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_stepTargetRefresh, refresh)) {
        _stepTargetRefresh = null;
      }
    }
  }

  Future<void> _performStepTargetRefresh() async {
    try {
      final status = await _samsungHealth.getStepTargetStatus();
      if (!mounted) return;
      if (status == SamsungHealthStatus.error) return;
      if (status != SamsungHealthStatus.connected) {
        setState(() => _stepTarget = null);
        return;
      }

      final target = await _samsungHealth.readStepTarget();
      if (!mounted) return;
      setState(() => _stepTarget = target);
    } catch (_) {
      final status = await _samsungHealth.getStepTargetStatus();
      if (!mounted) return;
      final targetIsCurrent =
          _stepTarget?.isForLocalDate(DateTime.now()) == true;
      final isTransient =
          status == SamsungHealthStatus.connected ||
          status == SamsungHealthStatus.error;
      if (!isTransient || !targetIsCurrent) {
        setState(() => _stepTarget = null);
      }
    } finally {
      if (mounted) {
        await _publishSnapshot();
      }
    }
  }

  Future<void> _refreshSleepTarget({bool refreshAgainIfBusy = false}) async {
    final activeRefresh = _sleepTargetRefresh;
    if (activeRefresh != null) {
      await activeRefresh;
      if (!refreshAgainIfBusy) return;
    }

    final refresh = _performSleepTargetRefresh();
    _sleepTargetRefresh = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_sleepTargetRefresh, refresh)) {
        _sleepTargetRefresh = null;
      }
    }
  }

  Future<void> _performSleepTargetRefresh() async {
    if (mounted) {
      setState(() {
        _syncingSleepTarget = true;
        _sleepTargetSyncFailed = false;
        _sleepTarget = null;
      });
    }
    try {
      final status = await _samsungHealth.getSleepTargetStatus();
      if (!mounted) return;
      setState(() {
        _sleepTargetStatus = status;
        _sleepTargetSyncFailed = status == SamsungHealthStatus.error;
      });
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
      final status = await _samsungHealth.getSleepTargetStatus();
      if (!mounted) return;
      setState(() {
        _sleepTarget = null;
        _sleepTargetStatus = status;
        _sleepTargetSyncFailed =
            status == SamsungHealthStatus.connected ||
            status == SamsungHealthStatus.error;
      });
    } finally {
      if (mounted) setState(() => _syncingSleepTarget = false);
    }
  }

  Future<void> _refreshHealthData() async {
    await Future.wait([
      _refreshSteps(),
      _refreshSleep(),
      _refreshStepTarget(),
      _refreshSleepTarget(),
    ]);
  }

  Future<void> _connectSteps() async {
    try {
      await _health.requestStepsPermission();
      await _refreshSteps();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Steps access was not enabled.')),
      );
    }
  }

  Future<void> _connectSleep() async {
    try {
      await _health.requestSleepPermission();
      await _refreshSleep();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sleep access was not enabled.')),
      );
    }
  }

  Future<void> _connectSleepTarget() async {
    if (_requestingSleepTarget) return;
    if (mounted) setState(() => _requestingSleepTarget = true);
    try {
      final granted = await _samsungHealth.requestSleepTargetPermission();
      await _refreshSleepTarget(refreshAgainIfBusy: true);
      if (!granted &&
          mounted &&
          _sleepTargetStatus == SamsungHealthStatus.permissionRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sleep target access was not enabled.')),
        );
      }
    } catch (_) {
      await _refreshSleepTarget(refreshAgainIfBusy: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sleep target access was not enabled.')),
      );
    } finally {
      if (mounted) setState(() => _requestingSleepTarget = false);
    }
  }

  Future<void> _openSettings() async {
    await showMoveSettings(context);
    final preferences = await _preferences.getPreferences();
    if (mounted) {
      setState(() {
        _goals = preferences.goals;
        _quickMovementIds = preferences.quickMovementIds;
      });
      await _publishSnapshot();
    }
    await _refreshHealthData();
  }

  Future<void> _customizeQuickMoves() async {
    final ids = await showQuickMovesEditor(
      context,
      initialIds: _quickMovementIds,
    );
    if (ids == null || !mounted) return;
    try {
      await _preferences.setQuickMovementIds(ids);
      if (!mounted) return;
      setState(() => _quickMovementIds = ids);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quick Moves updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update Quick Moves.')),
      );
    }
  }

  Future<void> _publishSnapshot() async {
    final movementAnalytics = MoveAnalytics(_logs);
    final stepAnalytics = StepAnalytics(_steps);
    final activity = ActivityAnalytics(
      movements: movementAnalytics,
      steps: stepAnalytics,
    );
    try {
      await _preferences.updateSnapshot(
        date: movementAnalytics.today,
        steps: stepAnalytics.todaySteps,
        movements: movementAnalytics.todayLogs.length,
        streak: activity.currentStreak,
        stepGoal: _effectiveGoals.stepGoal,
        usesSamsungStepGoal: _usesCurrentSamsungStepTarget,
      );
    } catch (_) {
      // Snapshot publishing only powers reminders and the home widget.
    }
  }

  Future<void> _retryLoad() async {
    await _loadInitialData();
    if (_loadError == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the local database.')),
      );
    }
  }

  Future<void> _openLogger({
    MovementDefinition? movement,
    MovementLog? existing,
  }) async {
    final log = await showMovementLogger(
      context,
      movement: movement,
      existing: existing,
    );
    if (log == null) return;

    try {
      if (log.id == null) {
        await _database.insertLog(log);
      } else {
        await _database.updateLog(log);
      }
      await _loadLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              log.id == null ? '${log.movement.name} logged' : 'Log updated',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that movement. Please try again.'),
        ),
      );
    }
  }

  Future<void> _deleteLog(MovementLog log) async {
    final id = log.id;
    if (id == null) return;
    final previousLogs = _logs;
    setState(() => _logs = _logs.where((item) => item.id != id).toList());
    await _publishSnapshot();
    try {
      await _database.deleteLog(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _logs = previousLogs);
      await _publishSnapshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete that log.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _MoveLoadingScreen();
    if (_loadError != null) return _MoveErrorScreen(onRetry: _retryLoad);

    final screens = [
      DashboardScreen(
        logs: _logs,
        steps: _steps,
        sleep: _sleep,
        goals: _effectiveGoals,
        sleepTarget: _sleepTarget,
        quickMovements: _quickMovementIds.map(MovementCatalog.byId).toList(),
        healthStatus: _healthStatus,
        sleepStatus: _sleepStatus,
        sleepTargetStatus: _sleepTargetStatus,
        syncingSteps: _syncingSteps,
        syncingSleep: _syncingSleep,
        syncingSleepTarget: _syncingSleepTarget || _requestingSleepTarget,
        stepSyncFailed: _stepSyncFailed,
        sleepSyncFailed: _sleepSyncFailed,
        sleepTargetSyncFailed: _sleepTargetSyncFailed,
        onLog: (movement) => _openLogger(movement: movement),
        onEdit: (log) => _openLogger(existing: log),
        onOpenHistory: () => setState(() => _tab = 1),
        onConnectSteps: _connectSteps,
        onConnectSleep: _connectSleep,
        onConnectSleepTarget: _connectSleepTarget,
        onRefreshHealthData: _refreshHealthData,
        onOpenSettings: _openSettings,
        onCustomizeQuickMoves: _customizeQuickMoves,
      ),
      HistoryScreen(
        logs: _logs,
        onEdit: (log) => _openLogger(existing: log),
        onDelete: _deleteLog,
      ),
      ProgressScreen(
        logs: _logs,
        steps: _steps,
        sleep: _sleep,
        goals: _effectiveGoals,
        sleepTarget: _sleepTarget,
        sleepTargetStatus: _sleepTargetStatus,
        sleepSyncFailed: _sleepSyncFailed,
        sleepTargetSyncFailed: _sleepTargetSyncFailed,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tab, children: screens),
      floatingActionButton: FloatingActionButton(
        onPressed: _openLogger,
        elevation: 3,
        tooltip: 'Log move',
        child: const Icon(Icons.add_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: MoveColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_rounded),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Progress',
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveLoadingScreen extends StatelessWidget {
  const _MoveLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: Image.asset('assets/icon/move_icon_foreground.png'),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveErrorScreen extends StatelessWidget {
  const _MoveErrorScreen({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.storage_rounded,
                color: MoveColors.danger,
                size: 46,
              ),
              const SizedBox(height: 16),
              Text(
                'Could not open your local data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Nothing was changed. Retry opening Move’s SQLite database.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
