import 'package:flutter/material.dart';

import 'repro_settings.dart';

/// Панель прогона: каждый переключатель меняет ровно одну переменную, чтобы
/// операцию, роняющую маркер, можно было выделить включением по одной.
class ControlsPanel extends StatelessWidget {
  const ControlsPanel({required this.settings, super.key});

  final ReproSettings settings;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    constraints: const BoxConstraints(maxHeight: 260),
    child: AnimatedBuilder(
      animation: settings,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        children: [
          _Row(
            label: 'iconMapDirection',
            child: _Choice<DirectionMode>(
              values: DirectionMode.values,
              current: settings.directionMode,
              labelOf: (v) => v.label,
              onPick: (v) => settings.directionMode = v,
            ),
          ),
          _Row(
            label: 'Трасса',
            child: _Choice<TrackKind>(
              values: TrackKind.values,
              current: settings.track,
              labelOf: (v) => v.label,
              onPick: (v) => settings.track = v,
            ),
          ),
          _Row(
            label: 'Маркеров',
            child: _Choice<int>(
              values: const [1, 5, 20],
              current: settings.markerCount,
              labelOf: (v) => '$v',
              onPick: (v) => settings.markerCount = v,
            ),
          ),
          _Row(
            label: 'Тик анимации',
            child: _Choice<int>(
              values: const [20, 30, 60],
              current: settings.tickHz,
              labelOf: (v) => '$v Гц',
              onPick: (v) => settings.tickHz = v,
            ),
          ),
          _Row(
            label: 'Ширина иконки',
            child: _Choice<double>(
              values: const [63, 96, 128],
              current: settings.iconWidth,
              labelOf: (v) => '${v.round()} lp',
              onPick: (v) => settings.iconWidth = v,
            ),
          ),
          _Row(
            label: 'Графика',
            child: _Choice<bool>(
              values: const [true, false],
              current: settings.liteGraphics,
              labelOf: (v) => v ? 'lite' : 'normal',
              onPick: (v) => settings.liteGraphics = v,
            ),
          ),
          _Toggle(
            label: 'animatedAppearance',
            value: settings.animatedAppearance,
            onChanged: (v) => settings.animatedAppearance = v,
          ),
          _Toggle(
            label: 'Линия маршрута',
            value: settings.routeVisible,
            onChanged: (v) => settings.routeVisible = v,
          ),
          _Toggle(
            label: 'Съедание erasedPart',
            value: settings.eraseRoute,
            onChanged: (v) => settings.eraseRoute = v,
          ),
          _Toggle(
            label: 'Маркер и линия в одном MapObjectManager',
            value: settings.sharedObjectManager,
            onChanged: (v) => settings.sharedObjectManager = v,
          ),
          _Toggle(
            label: 'Мигающий маршрут — раз в секунду',
            value: settings.blinkRoute,
            onChanged: (v) => settings.blinkRoute = v,
          ),
          _Toggle(
            label: 'Пересоздание линии раз в 20 с',
            value: settings.recreateRoute,
            onChanged: (v) => settings.recreateRoute = v,
          ),
          _Toggle(
            label: 'Камера следует за машиной',
            value: settings.followCamera,
            onChanged: (v) => settings.followCamera = v,
          ),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onPick,
  });

  final List<T> values;
  final T current;
  final String Function(T) labelOf;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(labelOf(value), style: const TextStyle(fontSize: 11)),
          selected: value == current,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => onPick(value),
        ),
    ],
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ],
  );
}
