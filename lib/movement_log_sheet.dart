import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'move_theme.dart';
import 'move_widgets.dart';

Future<MovementLog?> showMovementLogger(
  BuildContext context, {
  MovementDefinition? movement,
  MovementLog? existing,
}) {
  return showModalBottomSheet<MovementLog>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: MovementLogSheet(initialMovement: movement, existing: existing),
    ),
  );
}

class MovementLogSheet extends StatefulWidget {
  const MovementLogSheet({super.key, this.initialMovement, this.existing});

  final MovementDefinition? initialMovement;
  final MovementLog? existing;

  @override
  State<MovementLogSheet> createState() => _MovementLogSheetState();
}

class _MovementLogSheetState extends State<MovementLogSheet> {
  late MovementDefinition? _selected;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final _searchController = TextEditingController();
  MovementCategory? _category;
  MovementSide _side = MovementSide.both;

  @override
  void initState() {
    super.initState();
    _selected = widget.existing?.movement ?? widget.initialMovement;
    final initialAmount =
        widget.existing?.amount ?? _suggestedAmount(_selected);
    _amountController = TextEditingController(
      text: initialAmount == null ? '' : '$initialAmount',
    );
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
    _side = widget.existing?.side ?? MovementSide.both;
  }

  int? _suggestedAmount(MovementDefinition? movement) {
    if (movement == null || movement.presets.isEmpty) return null;
    return movement.presets.length > 1
        ? movement.presets[1]
        : movement.presets.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _chooseMovement(MovementDefinition movement) {
    setState(() {
      _selected = movement;
      _amountController.text = '${_suggestedAmount(movement)}';
      _side = MovementSide.both;
    });
  }

  void _adjustAmount(int change) {
    final current = int.tryParse(_amountController.text) ?? 0;
    final next = (current + change).clamp(1, 9999);
    setState(() => _amountController.text = '$next');
  }

  void _save() {
    final movement = _selected;
    final amount = int.tryParse(_amountController.text);
    if (movement == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount greater than zero.')),
      );
      return;
    }

    final now = DateTime.now();
    Navigator.of(context).pop(
      MovementLog(
        id: widget.existing?.id,
        movementId: movement.id,
        metric: movement.metric,
        amount: amount,
        side: movement.supportsSides ? _side : null,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        performedAt: widget.existing?.performedAt ?? now,
        createdAt: widget.existing?.createdAt ?? now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [...previousChildren, ?currentChild],
              ),
              child: _selected == null
                  ? _buildPicker()
                  : _buildAmountEditor(_selected!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = MovementCatalog.movements.where((movement) {
      final matchesCategory =
          _category == null || movement.category == _category;
      final matchesQuery =
          query.isEmpty ||
          movement.name.toLowerCase().contains(query) ||
          movement.description.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Padding(
      key: const ValueKey('movement-picker'),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Log movement',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'What did you just do?',
                      style: Theme.of(context).textTheme.bodyMedium,
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
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Find a movement',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 9,
            children: [
              _CategoryChip(
                label: 'All',
                selected: _category == null,
                onSelected: () => setState(() => _category = null),
              ),
              for (final category in MovementCategory.values)
                _CategoryChip(
                  label: category.label,
                  selected: _category == category,
                  onSelected: () => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 3, bottom: 20),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final movement = filtered[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 2,
                  ),
                  onTap: () => _chooseMovement(movement),
                  leading: MovementGlyph(movement: movement),
                  title: Text(
                    movement.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    '${movement.description} · ${movement.metric.label}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountEditor(MovementDefinition movement) {
    final editing = widget.existing != null;
    final canChooseMovement = !editing && widget.initialMovement == null;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final step = movement.metric == MetricType.reps ? 1 : 5;

    return SingleChildScrollView(
      key: ValueKey('amount-${movement.id}'),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 20 + keyboardInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: canChooseMovement
                    ? () => setState(() => _selected = null)
                    : () => Navigator.pop(context),
                icon: Icon(
                  canChooseMovement
                      ? Icons.arrow_back_rounded
                      : Icons.close_rounded,
                ),
              ),
              const Spacer(),
              Text(
                editing ? 'EDIT LOG' : 'NEW LOG',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: MoveColors.textSecondary,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(child: MovementGlyph(movement: movement, size: 64)),
          const SizedBox(height: 10),
          Text(
            movement.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            movement.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AdjustButton(
                icon: Icons.remove_rounded,
                onTap: () => _adjustAmount(-step),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 116,
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(fontSize: 42),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    suffixText: movement.metric == MetricType.reps ? '×' : 's',
                    suffixStyle: const TextStyle(
                      color: MoveColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              _AdjustButton(
                icon: Icons.add_rounded,
                onTap: () => _adjustAmount(step),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 9,
            runSpacing: 9,
            children: movement.presets.map((amount) {
              final selected = _amountController.text == '$amount';
              return ChoiceChip(
                selected: selected,
                onSelected: (_) =>
                    setState(() => _amountController.text = '$amount'),
                label: Text(
                  movement.metric == MetricType.reps
                      ? '$amount reps'
                      : formatCompactDuration(amount),
                ),
              );
            }).toList(),
          ),
          if (movement.supportsSides) ...[
            const SizedBox(height: 22),
            Text('SIDE', style: _fieldLabelStyle(context)),
            const SizedBox(height: 10),
            SegmentedButton<MovementSide>(
              segments: MovementSide.values
                  .map(
                    (side) =>
                        ButtonSegment(value: side, label: Text(side.label)),
                  )
                  .toList(),
              selected: {_side},
              onSelectionChanged: (selection) =>
                  setState(() => _side = selection.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.comfortable,
                side: const WidgetStatePropertyAll(
                  BorderSide(color: MoveColors.border),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('NOTE · OPTIONAL', style: _fieldLabelStyle(context)),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'How did it feel?',
              prefixIcon: Icon(Icons.notes_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: MoveColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                editing
                    ? DateFormat(
                        'MMM d · h:mm a',
                      ).format(widget.existing!.performedAt)
                    : 'Now · ${DateFormat('h:mm a').format(DateTime.now())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: Icon(editing ? Icons.check_rounded : Icons.add_rounded),
            label: Text(editing ? 'Save changes' : 'Log movement'),
          ),
        ],
      ),
    );
  }

  TextStyle? _fieldLabelStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(
      color: MoveColors.textSecondary,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    );
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 28,
      padding: const EdgeInsets.all(14),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}
