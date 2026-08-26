import 'dart:async';

import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'device_services.dart';
import 'history_screen.dart';
import 'models.dart';
import 'move_database.dart';
import 'move_settings_sheet.dart';
import 'move_theme.dart';
import 'movement_log_sheet.dart';
import 'progress_screen.dart';

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
  List<MovementLog> _logs = const [];
  List<DailyStepCount> _steps = const [];
  HealthConnectStatus? _healthStatus;
  bool _syncingSteps = false;
  bool _loading = true;
  String? _loadError;
  int _tab = 0;

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
      unawaited(_refreshSteps());
    }
  }

  Future<void> _loadInitialData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait<Object>([
        _database.getAllLogs(),
        _database.getDailySteps(),
      ]);
      if (!mounted) return;
      setState(() {
        _logs = values[0] as List<MovementLog>;
        _steps = values[1] as List<DailyStepCount>;
        _loading = false;
        _loadError = null;
      });
      unawaited(_refreshSteps());
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
    } catch (error) {
      if (!mounted) return;
      rethrow;
    }
  }

  Future<void> _refreshSteps() async {
    if (_syncingSteps) return;
    if (mounted) setState(() => _syncingSteps = true);
    try {
      final status = await _health.getStatus();
      if (!mounted) return;
      setState(() => _healthStatus = status);
      if (status != HealthConnectStatus.connected) return;

      final values = await _health.readDailySteps();
      await _database.upsertDailySteps(values);
      final cached = await _database.getDailySteps();
      if (!mounted) return;
      setState(() => _steps = cached);
    } catch (_) {
      // Cached step totals remain available if Health Connect cannot refresh.
    } finally {
      if (mounted) setState(() => _syncingSteps = false);
    }
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

  Future<void> _openSettings() async {
    await showMoveSettings(context);
    await _refreshSteps();
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
        healthStatus: _healthStatus,
        syncingSteps: _syncingSteps,
        onLog: (movement) => _openLogger(movement: movement),
        onEdit: (log) => _openLogger(existing: log),
        onOpenHistory: () => setState(() => _tab = 1),
        onConnectSteps: _connectSteps,
        onRefreshSteps: _refreshSteps,
        onOpenSettings: _openSettings,
      ),
      HistoryScreen(
        logs: _logs,
        onEdit: (log) => _openLogger(existing: log),
        onDelete: _deleteLog,
      ),
      ProgressScreen(logs: _logs, steps: _steps),
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
