import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

enum _HistoryFilter { all, reps, duration }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.logs,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MovementLog> logs;
  final ValueChanged<MovementLog> onEdit;
  final Future<void> Function(MovementLog) onDelete;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;

  List<MovementLog> get _filtered {
    return widget.logs.where((log) {
      return switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.reps => log.metric == MetricType.reps,
        _HistoryFilter.duration => log.metric == MetricType.duration,
      };
    }).toList();
  }

  Future<bool> _confirmDelete(MovementLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this log?'),
        content: Text(
          '${log.movement.name} · ${formatAmount(log.metric, log.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: MoveColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filtered;
    final groups = <DateTime, List<MovementLog>>{};
    for (final log in logs) {
      final day = DateTime(
        log.performedAt.year,
        log.performedAt.month,
        log.performedAt.day,
      );
      groups.putIfAbsent(day, () => []).add(log);
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.logs.length} total set${widget.logs.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_HistoryFilter>(
                      segments: const [
                        ButtonSegment(
                          value: _HistoryFilter.all,
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: _HistoryFilter.reps,
                          label: Text('Reps'),
                        ),
                        ButtonSegment(
                          value: _HistoryFilter.duration,
                          label: Text('Duration'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (selection) =>
                          setState(() => _filter = selection.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        side: WidgetStatePropertyAll(
                          BorderSide(color: MoveColors.border),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (logs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.history_rounded,
                title: 'No movement logs yet',
                message: 'Use the + button to log something you did.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 104),
              sliver: SliverList.list(
                children: groups.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 6),
                          child: Text(
                            _dayLabel(entry.key),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: MoveColors.textSecondary),
                          ),
                        ),
                        SurfaceCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 3,
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < entry.value.length; i++) ...[
                                Dismissible(
                                  key: ValueKey('log-${entry.value[i].id}'),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) =>
                                      _confirmDelete(entry.value[i]),
                                  onDismissed: (_) =>
                                      widget.onDelete(entry.value[i]),
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 18),
                                    decoration: BoxDecoration(
                                      color: MoveColors.danger.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: MoveColors.danger,
                                    ),
                                  ),
                                  child: LogTile(
                                    log: entry.value[i],
                                    onTap: () => widget.onEdit(entry.value[i]),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: MoveColors.textSecondary,
                                      size: 19,
                                    ),
                                  ),
                                ),
                                if (i != entry.value.length - 1)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _dayLabel(DateTime date) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (date == todayDate) return 'Today';
    if (date == DateTime(todayDate.year, todayDate.month, todayDate.day - 1)) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMMM d').format(date);
  }
}
