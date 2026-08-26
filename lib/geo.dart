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

/// Индекс трассы с накопленными расстояниями: без него каждая выборка точки
/// обходит ломаную с начала, а сглаживание курса требует их десятками на тик.
class TrackIndex {
  TrackIndex(this.points) : _cumulative = _buildCumulative(points);

  final List<LatLng> points;
  final List<double> _cumulative;

  static List<double> _buildCumulative(List<LatLng> points) {
    final result = <double>[0];
    for (var i = 1; i < points.length; i++) {
      result.add(result[i - 1] + haversineMeters(points[i - 1], points[i]));
    }
    return result;
  }

  double get lengthMeters => _cumulative.isEmpty ? 0 : _cumulative.last;

  /// Номер отрезка, на который попадает отметка.
  int segmentAt(double meters) {
    var low = 0;
    var high = _cumulative.length - 1;
    while (low < high - 1) {
      final middle = (low + high) ~/ 2;
      if (_cumulative[middle] <= meters) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  LatLng pointAt(double meters) {
    if (points.length < 2) return points.first;
    final s = meters.clamp(0.0, lengthMeters);
    final i = segmentAt(s);
    final segment = _cumulative[i + 1] - _cumulative[i];
    if (segment <= 0) return points[i];
    return lerpPoint(points[i], points[i + 1], (s - _cumulative[i]) / segment);
  }

  double bearingAt(double meters) {
    if (points.length < 2) return 0;
    final i = segmentAt(meters.clamp(0.0, lengthMeters));
    return bearingDegrees(points[i], points[i + 1]);
  }

  /// Центроид ломаной на участке — среднее по длине дуги. Для ломаной точен:
  /// центроид отрезка равен его середине.
  LatLng _centroid(double fromMeters, double toMeters) {
    final start = fromMeters.clamp(0.0, lengthMeters);
    final end = toMeters.clamp(0.0, lengthMeters);
    if (end <= start) return pointAt(start);

    var weight = 0.0;
    var lat = 0.0;
    var lon = 0.0;
    var cursor = start;
    var i = segmentAt(start);
    while (cursor < end && i < points.length - 1) {
      final segmentEnd = _cumulative[i + 1];
      final pieceEnd = segmentEnd < end ? segmentEnd : end;
      final piece = pieceEnd - cursor;
      if (piece > 0) {
        final middle = pointAt((cursor + pieceEnd) / 2);
        lat += middle.lat * piece;
        lon += middle.lon * piece;
        weight += piece;
      }
      cursor = pieceEnd;
      i++;
    }
    if (weight == 0) return pointAt(start);
    return LatLng(lat / weight, lon / weight);
  }

  /// Точка ведущей кривой. Полуокно сжимается у концов трассы: несимметричное
  /// обрезание сдвинуло бы старт вперёд на четверть окна.
  LatLng guidePoint(double meters, double windowMeters) {
    var half = windowMeters / 2;
    if (meters < half) half = meters;
    if (lengthMeters - meters < half) half = lengthMeters - meters;
    if (half <= 0) return pointAt(meters);
    return _centroid(meters - half, meters + half);
  }

  /// Поза на ведущей кривой: и точка, и курс меняются непрерывно. Курс по
  /// касательной к отрезку держится постоянным на прямой и скачет на вершине —
  /// а запись неизменного значения в маркер движок пропускает, и проверяемая
  /// операция не выполняется вовсе.
  ({LatLng point, double bearing}) smoothedPose(
    double meters, {
    double windowMeters = 24.0,
    double deltaMeters = 1.0,
  }) {
    final s = meters.clamp(0.0, lengthMeters);
    final point = guidePoint(s, windowMeters);
    final back = guidePoint((s - deltaMeters).clamp(0.0, lengthMeters), windowMeters);
    final ahead = guidePoint((s + deltaMeters).clamp(0.0, lengthMeters), windowMeters);
    if (haversineMeters(back, ahead) < 0.01) {
      return (point: point, bearing: bearingAt(s));
    }
    return (point: point, bearing: bearingDegrees(back, ahead));
  }
}
