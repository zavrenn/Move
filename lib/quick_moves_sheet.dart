import 'package:flutter/material.dart';

import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

Future<List<String>?> showQuickMovesEditor(
  BuildContext context, {
  required List<String> initialIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _QuickMovesSheet(initialIds: initialIds),
    ),
  );
}

class _QuickMovesSheet extends StatefulWidget {
  const _QuickMovesSheet({required this.initialIds});

  final List<String> initialIds;

  @override
  State<_QuickMovesSheet> createState() => _QuickMovesSheetState();
}

class _QuickMovesSheetState extends State<_QuickMovesSheet> {
  late final List<String> _ids = List.of(widget.initialIds);

  Future<void> _addMovement() async {
    if (_ids.length >= 8) return;
    final movement = await showModalBottomSheet<MovementDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.78,
        child: _AvailableMovementSheet(excludedIds: _ids.toSet()),
      ),
    );
    if (movement == null || !mounted) return;
    setState(() => _ids.add(movement.id));
  }

  void _remove(String id) {
    if (_ids.length <= 2) return;
    setState(() => _ids.remove(id));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final id = _ids.removeAt(oldIndex);
      _ids.insert(newIndex, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetSurface(
      child: Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Moves',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_ids.length} selected · drag to reorder',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              buildDefaultDragHandles: false,
              itemCount: _ids.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) {
                final movement = MovementCatalog.byId(_ids[index]);
                return Padding(
                  key: ValueKey(movement.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                    child: Row(
                      children: [
                        MovementGlyph(movement: movement, size: 38),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                movement.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                movement.metric.label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _ids.length > 2
                              ? () => _remove(movement.id)
                              : null,
                          tooltip: 'Remove ${movement.name}',
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                        ReorderableDelayedDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: MoveColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ids.length < 8 ? _addMovement : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, List.of(_ids)),
                    child: const Text('Save order'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableMovementSheet extends StatefulWidget {
  const _AvailableMovementSheet({required this.excludedIds});

  final Set<String> excludedIds;

  @override
  State<_AvailableMovementSheet> createState() =>
      _AvailableMovementSheetState();
}

class _AvailableMovementSheetState extends State<_AvailableMovementSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final available = MovementCatalog.movements.where((movement) {
      if (widget.excludedIds.contains(movement.id)) return false;
      return query.isEmpty ||
          movement.name.toLowerCase().contains(query) ||
          movement.description.toLowerCase().contains(query);
    }).toList();

    return _SheetSurface(
      child: Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add a Quick Move',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Find a movement',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              itemCount: available.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final movement = available[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  onTap: () => Navigator.pop(context, movement),
                  leading: MovementGlyph(movement: movement, size: 40),
                  title: Text(movement.name),
                  subtitle: Text(movement.description),
                  trailing: const Icon(Icons.add_circle_outline_rounded),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MoveColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: MoveColors.border)),
      ),
      child: child,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: MoveColors.border,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
