import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'repro_scene.dart';

/// Кадры и записи в SDK рядом. Смысл соседства: во время моргания растр
/// продолжает идти — линия съедается, камера едет, — а маркера в кадре нет.
/// Ровный `frames/s` при провале на записи экрана и есть доказательство, что
/// теряется отрисовка маркера, а не кадр целиком.
class FrameHud extends StatefulWidget {
  const FrameHud({required this.stats, super.key});

  final ValueNotifier<ReproStats> stats;

  @override
  State<FrameHud> createState() => _FrameHudState();
}

class _FrameHudState extends State<FrameHud> {
  static const _window = Duration(seconds: 10);
  static const _slowFrameMicros = 16700;

  final _frames = <({DateTime at, int buildMicros, int rasterMicros})>[];
  final DateTime _startedAt = DateTime.now();
  Timer? _repaint;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _repaint = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _repaint?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    for (final timing in timings) {
      _frames.add((
        at: now,
        buildMicros: timing.buildDuration.inMicroseconds,
        rasterMicros: timing.rasterDuration.inMicroseconds,
      ));
    }
    _frames.removeWhere((f) => now.difference(f.at) > _window);
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    final slow = frames.where((f) => f.rasterMicros > _slowFrameMicros).length;
    final raster = frames.isEmpty
        ? 0.0
        : frames.map((f) => f.rasterMicros).reduce((a, b) => a + b) /
              frames.length /
              1000.0;
    final fps = frames.length / _window.inSeconds;
    final seconds = DateTime.now().difference(_startedAt).inSeconds;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 6, 52, 6),
      child: ValueListenableBuilder<ReproStats>(
        valueListenable: widget.stats,
        builder: (_, stats, _) => DefaultTextStyle(
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'кадры ${fps.toStringAsFixed(0)}/с · растр '
                '${raster.toStringAsFixed(1)} мс · медленных $slow',
              ),
              Text('t=$seconds с'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Вторая строка HUD: что именно уехало в SDK за последнюю секунду.
class WritesHud extends StatelessWidget {
  const WritesHud({required this.stats, super.key});

  final ValueNotifier<ReproStats> stats;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(10, 6, 52, 6),
    child: ValueListenableBuilder<ReproStats>(
      valueListenable: stats,
      builder: (_, s, _) => DefaultTextStyle(
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        child: Text(
          'position ${s.positionWrites}/с · direction ${s.directionWrites}/с '
          '(новых ${s.directionChanges}) · erasedPart ${s.erasedWrites}/с',
        ),
      ),
    ),
  );
}
