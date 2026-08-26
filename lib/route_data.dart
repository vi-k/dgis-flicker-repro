import 'dart:math' as math;

import 'geo.dart';

/// Вершины маршрута из диагностики тикета (Алматы). Ровно те же, на которых
/// симптом снимали в приложении.
const routeVertices = <LatLng>[
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

/// Боевая трасса: длинные прямые, курс между вершинами почти не меняется.
final List<LatLng> straightTrack = densify(routeVertices, _stepMeters);

/// Змейка поверх той же трассы: курс ходит примерно ±45°, то есть за анимацию
/// иконка доворачивается на десятки градусов — как в поездке QA.
final List<LatLng> serpentineTrack = _serpentine(straightTrack);

const _serpentineAmplitudeMeters = 25.0;
const _serpentinePeriodMeters = 150.0;

List<LatLng> _serpentine(List<LatLng> track) {
  final result = <LatLng>[];
  var along = 0.0;
  for (var i = 0; i < track.length; i++) {
    if (i > 0) along += haversineMeters(track[i - 1], track[i]);
    final heading = i == 0
        ? bearingDegrees(track[0], track[1])
        : bearingDegrees(track[i - 1], track[i]);
    final shift =
        _serpentineAmplitudeMeters *
        math.sin(2 * math.pi * along / _serpentinePeriodMeters);
    result.add(_offset(track[i], shift, heading + 90.0));
  }
  return result;
}

const _metersPerDegreeLat = 111320.0;

LatLng _offset(LatLng point, double meters, double bearingDegrees) {
  final rad = bearingDegrees * math.pi / 180.0;
  final dLat = meters * math.cos(rad) / _metersPerDegreeLat;
  final dLon =
      meters *
      math.sin(rad) /
      (_metersPerDegreeLat * math.cos(point.lat * math.pi / 180.0));
  return LatLng(point.lat + dLat, point.lon + dLon);
}
