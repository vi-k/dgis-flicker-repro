import 'dart:math' as math;

import 'geo.dart';

/// Вершины маршрута из диагностики тикета (Алматы) — те же, на которых симптом
/// снимали в приложении.
const _vertices = <LatLng>[
  LatLng(43.17356, 77.02523),
  LatLng(43.17190, 77.03551),
  LatLng(43.17064, 77.03812),
  LatLng(43.16990, 77.03939),
  LatLng(43.16942, 77.03984),
  LatLng(43.16799, 77.04073),
  LatLng(43.16662, 77.04171),
  LatLng(43.16525, 77.04157),
  LatLng(43.16308749, 77.05034466),
];

const _stepMeters = 20.0;
const _amplitudeMeters = 25.0;
const _periodMeters = 150.0;

/// Трасса-змейка поверх вершин из тикета: курс ходит примерно ±45°, поэтому за
/// каждый тик направление меняется заметно. На прямой курс держится постоянным,
/// а запись неизменного значения движок пропускает — тогда проверяемая операция
/// не выполняется вовсе.
final List<LatLng> track = _serpentine(densify(_vertices, _stepMeters));

List<LatLng> _serpentine(List<LatLng> base) {
  final result = <LatLng>[];
  var along = 0.0;
  for (var i = 0; i < base.length; i++) {
    if (i > 0) along += haversineMeters(base[i - 1], base[i]);
    final heading = i == 0
        ? bearingDegrees(base[0], base[1])
        : bearingDegrees(base[i - 1], base[i]);
    final shift = _amplitudeMeters * math.sin(2 * math.pi * along / _periodMeters);
    result.add(_offset(base[i], shift, heading + 90.0));
  }
  return result;
}

const _metersPerDegreeLat = 111320.0;

LatLng _offset(LatLng point, double meters, double bearingDegrees) {
  final rad = bearingDegrees * math.pi / 180.0;
  final dLat = meters * math.cos(rad) / _metersPerDegreeLat;
  final dLon = meters *
      math.sin(rad) /
      (_metersPerDegreeLat * math.cos(point.lat * math.pi / 180.0));
  return LatLng(point.lat + dLat, point.lon + dLon);
}
