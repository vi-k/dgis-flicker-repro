import 'package:flutter/material.dart';

import 'repro_settings.dart';

/// Панель прогона: частота записи направления в маркер и доли съеденного в
/// полилинию. Каждая ручка меняет ровно одно свойство ровно одного объекта.
class ControlsPanel extends StatelessWidget {
  const ControlsPanel({required this.settings, super.key});

  final ReproSettings settings;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
    child: AnimatedBuilder(
      animation: settings,
      builder: (_, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Row(
            label: 'Машина\niconMapDirection',
            current: settings.direction,
            onPick: (v) => settings.direction = v,
          ),
          const SizedBox(height: 6),
          _Row(
            label: 'Трек\nerasedPart',
            current: settings.erased,
            onPick: (v) => settings.erased = v,
          ),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.current,
    required this.onPick,
  });

  final String label;
  final WriteRate current;
  final ValueChanged<WriteRate> onPick;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 140,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
      Expanded(
        child: Wrap(
          spacing: 4,
          children: [
            for (final rate in WriteRate.values)
              ChoiceChip(
                label: Text(rate.label, style: const TextStyle(fontSize: 11)),
                selected: rate == current,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => onPick(rate),
              ),
          ],
        ),
      ),
    ],
  );
}
