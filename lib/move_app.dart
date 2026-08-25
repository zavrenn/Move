import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'models.dart';
import 'move_database.dart';
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

class _MoveShellState extends State<MoveShell> {
  final _database = MoveDatabase.instance;
  List<MovementLog> _logs = const [];
  bool _loading = true;
  String? _loadError;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      final logs = await _database.getAllLogs();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
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
    if (_loadError != null) return _MoveErrorScreen(onRetry: _loadLogs);

    final screens = [
      DashboardScreen(
        logs: _logs,
        onLog: (movement) => _openLogger(movement: movement),
        onEdit: (log) => _openLogger(existing: log),
        onOpenHistory: () => setState(() => _tab = 1),
      ),
      HistoryScreen(
        logs: _logs,
        onEdit: (log) => _openLogger(existing: log),
        onDelete: _deleteLog,
      ),
      ProgressScreen(logs: _logs),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tab, children: screens),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openLogger,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: const Text('LOG MOVE'),
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
