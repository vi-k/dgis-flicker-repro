import 'dart:async';

import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'package:flutter/foundation.dart';

import 'car_icon.dart';
import 'geo.dart';
import 'repro_settings.dart';
import 'route_data.dart';

/// Счётчики за последнюю секунду. `directionChanges` считает записи с новым
/// значением: запись, совпавшую с прежней, движок пропускает, и переукладки
/// объекта не делает — без этого счётчика настоящую запись не отличить от
/// пустой.
class ReproStats {
  const ReproStats({
    this.positionWrites = 0,
    this.directionWrites = 0,
    this.directionChanges = 0,
    this.erasedWrites = 0,
  });

  final int positionWrites;
  final int directionWrites;
  final int directionChanges;
  final int erasedWrites;
}

/// Сцена прогона: полилиния маршрута и маркер машины, которые едут по трассе.
/// Всё, кроме частоты записей, закреплено на значениях приложения: тик 60 Гц,
/// иконка 63 логических пикселя, `GraphicsPreset.lite`,
/// `animatedAppearance: false`, камера следует за машиной.
class ReproScene {
  ReproScene({
    required this.context,
    required this.map,
    required this.settings,
    required this.devicePixelRatio,
  });

  final sdk.Context context;
  final sdk.Map map;
  final ReproSettings settings;
  final double devicePixelRatio;

  final stats = ValueNotifier<ReproStats>(const ReproStats());

  late final sdk.MapObjectManager _objects = sdk.MapObjectManager(map);
  late final sdk.ImageLoader _loader = sdk.ImageLoader(context);

  /// Событие с новой точкой водителя. Медиана по логу поездки — 5.43 с.
  static const _eventPeriod = Duration(milliseconds: 5400);

  /// Потолок анимации: отрезок проезжается за две секунды, остаток периода
  /// машина стоит.
  static const _animationDuration = Duration(milliseconds: 2000);

  /// Путь за одно событие: 75 м за 5.4 с — около 50 км/ч.
  static const _metersPerEvent = 75.0;

  /// Тик сцены. Частоту записей задают ручки, тик всегда максимальный.
  static const _tick = Duration(milliseconds: 16);

  static const _routeColor = sdk.Color(0xFF00A025);
  static const _routeWidth = sdk.LogicalPixel(4);
  static const _iconWidth = sdk.LogicalPixel(63);

  Timer? _tickTimer;
  Timer? _eventTimer;
  Timer? _statsTimer;
  Timer? _directionTimer;
  Timer? _erasedTimer;
  WriteRate? _directionRate;
  WriteRate? _erasedRate;

  sdk.Marker? _marker;
  sdk.Polyline? _polyline;

  late final TrackIndex _index = TrackIndex(track);
  double _routeOffsetMeters = 0;
  double _routeLengthMeters = 0;

  double _traveled = 0;
  double _segmentFrom = 0;
  double _segmentTo = 0;
  DateTime? _animationStartedAt;

  double? _lastWrittenBearing;

  int _positionWrites = 0;
  int _directionWrites = 0;
  int _directionChanges = 0;
  int _erasedWrites = 0;
  bool _disposed = false;

  Future<void> start() async {
    map.graphicsPreset = sdk.GraphicsPreset.lite;
    await _addMarker();
    if (_disposed) return;
    _rebuildRoute(fromMeters: 0);
    settings.addListener(_restartWriteTimers);
    _restartWriteTimers();
    _tickTimer = Timer.periodic(_tick, (_) => _onTick());
    _eventTimer = Timer.periodic(_eventPeriod, (_) => _onDriverEvent());
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _flushStats(),
    );
    _onDriverEvent();
  }

  void dispose() {
    _disposed = true;
    settings.removeListener(_restartWriteTimers);
    _directionTimer?.cancel();
    _erasedTimer?.cancel();
    _tickTimer?.cancel();
    _eventTimer?.cancel();
    _statsTimer?.cancel();
    final marker = _marker;
    if (marker != null) _objects.removeObject(marker);
    _removePolyline();
    stats.dispose();
  }

  Future<void> _addMarker() async {
    final pixels = (_iconWidth.value * devicePixelRatio).round();
    final png = await buildCarIconPng(pixels);
    if (_disposed) return;
    final icon = _loader.loadPngFromByteData(png, pixels, pixels);
    final pose = _index.smoothedPose(0);
    final marker = sdk.Marker(
      sdk.MarkerOptions(
        position: _withElevation(pose.point),
        icon: icon,
        iconWidth: _iconWidth,
        iconMapDirection: sdk.MapDirection(pose.bearing),
        zIndex: const sdk.ZIndex(100),
        // Дефолт SDK — анимировать появление. С ним переукладка иконки видна
        // как полупрозрачность, без него — как полная пропажа.
        animatedAppearance: false,
      ),
    );
    _marker = marker;
    _objects.addObject(marker);
  }

  void _rebuildRoute({required double fromMeters}) {
    _removePolyline();
    final tail = _tailFrom(fromMeters);
    if (tail.points.length < 2) return;
    _routeOffsetMeters = tail.offsetMeters;
    _routeLengthMeters = polylineLengthMeters(tail.points);
    final polyline = sdk.Polyline(
      sdk.PolylineOptions(
        points: tail.points.map(_toSdkPoint).toList(),
        width: _routeWidth,
        color: _routeColor,
      ),
    );
    _polyline = polyline;
    _objects.addObject(polyline);
  }

  ({List<LatLng> points, double offsetMeters}) _tailFrom(double meters) {
    var walked = 0.0;
    for (var i = 1; i < track.length; i++) {
      final segment = haversineMeters(track[i - 1], track[i]);
      if (walked + segment > meters) {
        return (points: track.sublist(i - 1), offsetMeters: walked);
      }
      walked += segment;
    }
    return (points: const <LatLng>[], offsetMeters: walked);
  }

  void _removePolyline() {
    final polyline = _polyline;
    _polyline = null;
    _routeLengthMeters = 0;
    if (polyline != null) _objects.removeObject(polyline);
  }

  void _onDriverEvent() {
    _segmentFrom = _traveled;
    _segmentTo = _traveled + _metersPerEvent;
    var wrapped = false;
    if (_segmentTo >= _index.lengthMeters) {
      // Трасса кончилась — начинаем сначала.
      _traveled = 0;
      _segmentFrom = 0;
      _segmentTo = _metersPerEvent;
      _rebuildRoute(fromMeters: 0);
      wrapped = true;
    }
    _animationStartedAt = DateTime.now();
    // На заворачивании камера обязана прыгнуть: машина переносится в начало
    // мгновенно, и перелёт оставил бы её вне кадра — на записи это неотличимо
    // от пропажи маркера.
    _moveCamera(instant: wrapped);
  }

  void _onTick() {
    final startedAt = _animationStartedAt;
    final marker = _marker;
    if (startedAt == null || marker == null) return;

    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final t = (elapsed / _animationDuration.inMilliseconds).clamp(0.0, 1.0);
    final along = _segmentFrom + (_segmentTo - _segmentFrom) * t;
    final pose = _index.smoothedPose(along);
    _traveled = along;

    marker.position = _withElevation(pose.point);
    _positionWrites++;

    if (t >= 1.0) _animationStartedAt = null;
  }

  /// Таймеры записей живут отдельно от тика сцены, чтобы частота была ровно
  /// такой, какая выбрана ручкой.
  void _restartWriteTimers() {
    if (settings.direction != _directionRate) {
      _directionRate = settings.direction;
      _directionTimer?.cancel();
      final period = settings.direction.period;
      _directionTimer = period == null
          ? null
          : Timer.periodic(period, (_) => _writeDirection());
    }
    if (settings.erased != _erasedRate) {
      _erasedRate = settings.erased;
      _erasedTimer?.cancel();
      final period = settings.erased.period;
      _erasedTimer = period == null
          ? null
          : Timer.periodic(period, (_) => _writeErasedPart());
    }
  }

  /// Порогов по величине изменения здесь нет намеренно: каждая запись несёт
  /// новое значение, иначе движок её пропустит и проверяемая операция не
  /// выполнится. Между событиями машина стоит и значение не меняется — тогда
  /// не пишем вовсе, иначе счётчик показывал бы записи, которых движок не
  /// видит.
  void _writeDirection() {
    final marker = _marker;
    if (marker == null || _animationStartedAt == null) return;
    final bearing = _index.smoothedPose(_traveled).bearing;

    final previous = _lastWrittenBearing;
    if (previous == null || (bearing - previous).abs() > 0.001) {
      _directionChanges++;
    }
    _lastWrittenBearing = bearing;
    marker.iconMapDirection = sdk.MapDirection(bearing);
    _directionWrites++;
  }

  void _writeErasedPart() {
    final polyline = _polyline;
    if (polyline == null ||
        _routeLengthMeters <= 0 ||
        _animationStartedAt == null) {
      return;
    }
    polyline.erasedPart =
        ((_traveled - _routeOffsetMeters) / _routeLengthMeters).clamp(0.0, 1.0);
    _erasedWrites++;
  }

  void _moveCamera({bool instant = false}) {
    final pose = _index.smoothedPose(_segmentTo);
    unawaited(
      map.camera
          .moveToCameraPosition(
            sdk.CameraPosition(
              point: _toSdkPoint(pose.point),
              zoom: const sdk.Zoom(16),
              tilt: const sdk.Tilt(0),
              bearing: const sdk.Bearing(0),
            ),
            instant ? Duration.zero : _animationDuration,
            sdk.CameraAnimationType.linear,
          )
          .value,
    );
  }

  void _flushStats() {
    stats.value = ReproStats(
      positionWrites: _positionWrites,
      directionWrites: _directionWrites,
      directionChanges: _directionChanges,
      erasedWrites: _erasedWrites,
    );
    _positionWrites = 0;
    _directionWrites = 0;
    _directionChanges = 0;
    _erasedWrites = 0;
  }

  static sdk.GeoPoint _toSdkPoint(LatLng point) => sdk.GeoPoint(
    latitude: sdk.Latitude(point.lat),
    longitude: sdk.Longitude(point.lon),
  );

  static sdk.GeoPointWithElevation _withElevation(LatLng point) =>
      sdk.GeoPointWithElevation(
        latitude: sdk.Latitude(point.lat),
        longitude: sdk.Longitude(point.lon),
      );
}
