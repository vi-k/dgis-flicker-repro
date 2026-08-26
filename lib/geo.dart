import 'dart:math' as math;

/// Точка в градусах. Своя, чтобы вычисления не зависели от типов SDK.
class LatLng {
  const LatLng(this.lat, this.lon);

  final double lat;
  final double lon;
}

const _earthRadiusMeters = 6371008.8;

double _rad(double degrees) => degrees * math.pi / 180.0;

double _deg(double radians) => radians * 180.0 / math.pi;

double haversineMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(h)));
}

double bearingDegrees(LatLng from, LatLng to) {
  final dLon = _rad(to.lon - from.lon);
  final y = math.sin(dLon) * math.cos(_rad(to.lat));
  final x =
      math.cos(_rad(from.lat)) * math.sin(_rad(to.lat)) -
      math.sin(_rad(from.lat)) * math.cos(_rad(to.lat)) * math.cos(dLon);
  return (_deg(math.atan2(y, x)) + 360.0) % 360.0;
}

/// Линейная интерполяция по градусам: на десятках метров разница с точной
/// формулой ниже сантиметра.
LatLng lerpPoint(LatLng a, LatLng b, double t) =>
    LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);

/// Сгущает ломаную до шага не крупнее [stepMeters]: без этого курс касательной
/// меняется скачком на вершинах, а нам нужен плавный поворот.
List<LatLng> densify(List<LatLng> source, double stepMeters) {
  if (source.length < 2) return List<LatLng>.of(source);
  final result = <LatLng>[source.first];
  for (var i = 1; i < source.length; i++) {
    final from = source[i - 1];
    final to = source[i];
    final segment = haversineMeters(from, to);
    final parts = math.max(1, (segment / stepMeters).ceil());
    for (var p = 1; p <= parts; p++) {
      result.add(lerpPoint(from, to, p / parts));
    }
  }
  return result;
}

double polylineLengthMeters(List<LatLng> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += haversineMeters(points[i - 1], points[i]);
  }
  return total;
}

/// Точка на ломаной по пройденному расстоянию и курс касательной в ней.
({LatLng point, double bearing}) poseAlong(List<LatLng> points, double meters) {
  if (points.length < 2) {
    return (point: points.first, bearing: 0.0);
  }
  var left = meters.clamp(0.0, double.infinity);
  for (var i = 1; i < points.length; i++) {
    final from = points[i - 1];
    final to = points[i];
    final segment = haversineMeters(from, to);
    if (segment <= 0) continue;
    if (left <= segment) {
      return (
        point: lerpPoint(from, to, left / segment),
        bearing: bearingDegrees(from, to),
      );
    }
    left -= segment;
  }
  final last = points.length - 1;
  return (
    point: points[last],
    bearing: bearingDegrees(points[last - 1], points[last]),
  );
}
