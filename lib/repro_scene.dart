import 'dart:async';
import 'dart:math' as math;

import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'package:flutter/foundation.dart';

import 'car_icon.dart';
import 'geo.dart';
import 'repro_settings.dart';
import 'route_data.dart';

/// Счётчики записей в SDK за последнюю секунду — HUD показывает их рядом с
/// кадрами, чтобы моргание можно было сопоставить с тем, что писалось.
class ReproStats {
  const ReproStats({
    this.positionWrites = 0,
    this.directionWrites = 0,
    this.erasedWrites = 0,
    this.routeRecreates = 0,
    this.animating = false,
  });

  final int positionWrites;
  final int directionWrites;
  final int erasedWrites;
  final int routeRecreates;
  final bool animating;
}

/// Сцена прогона: маршрут-полилиния, маркер машины и таймеры, которые пишут в
/// них ровно то же, что боевой трекер, — позицию каждый тик, направление по
/// выбранному режиму, `erasedPart` не чаще десяти раз в секунду.
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

  /// Машина живёт в отдельном менеджере от маршрута — так же, как в боевом
  /// коде: пересоздание полилинии не должно задевать маркер.
  late final sdk.MapObjectManager _routeObjects = sdk.MapObjectManager(map);
  late final sdk.MapObjectManager _carObjects = sdk.MapObjectManager(map);
  late final sdk.ImageLoader _loader = sdk.ImageLoader(context);

  /// Событие с новой точкой водителя. Медиана по логу поездки QA — 5.43 с.
  static const _eventPeriod = Duration(milliseconds: 5400);

  /// Потолок анимации боевого трекера: отрезок проезжается за две секунды,
  /// остаток периода машина стоит.
  static const _animationDuration = Duration(milliseconds: 2000);

  /// Путь за одно событие: 75 м за 5.4 с — около 50 км/ч.
  static const _metersPerEvent = 75.0;

  /// Пересылка маршрута с новой геометрией — как в бою, раз в 20 с.
  static const _routeResendPeriod = Duration(seconds: 20);

  /// `erasedPart` пишется не чаще десяти раз в секунду (боевой предел).
  static const _eraseInterval = Duration(milliseconds: 100);

  static const _routeColor = sdk.Color(0xFF00A025);
  static const _routeWidth = sdk.LogicalPixel(4);

  /// Кольцо вспомогательных маркеров вокруг машины — ручка усиления.
  static const _extraMarkerRadiusMeters = 40.0;

  Timer? _tickTimer;
  Timer? _eventTimer;
  Timer? _routeTimer;
  Timer? _statsTimer;

  final _markers = <sdk.Marker>[];
  sdk.Polyline? _polyline;
  sdk.Image? _icon;
  int _iconPixels = 0;

  List<LatLng> _track = const [];
  double _trackLength = 0;

  /// Геометрия текущей полилинии и то, сколько трассы осталось до её начала:
  /// пересланный маршрут начинается от машины, а не от старта.
  List<LatLng> _routePoints = const [];
  double _routeOffsetMeters = 0;
  double _routeLengthMeters = 0;

  double _traveled = 0;
  double _segmentFrom = 0;
  double _segmentTo = 0;
  DateTime? _animationStartedAt;

  DateTime? _lastDirectionWriteAt;
  DateTime? _lastEraseAt;
  double? _lastErasedPart;

  int _positionWrites = 0;
  int _directionWrites = 0;
  int _erasedWrites = 0;
  int _routeRecreates = 0;
  int _appliedObjectsRevision = -1;
  bool _disposed = false;

  Future<void> start() async {
    map.graphicsPreset = settings.liteGraphics
        ? sdk.GraphicsPreset.lite
        : sdk.GraphicsPreset.normal;
    settings.addListener(_onSettingsChanged);
    await _rebuildObjects();
    _restartTickTimer();
    _eventTimer = Timer.periodic(_eventPeriod, (_) => _onDriverEvent());
    _routeTimer = Timer.periodic(_routeResendPeriod, (_) => _onRouteResend());
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _flushStats());
    _onDriverEvent();
  }

  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
    _tickTimer?.cancel();
    _eventTimer?.cancel();
    _routeTimer?.cancel();
    _statsTimer?.cancel();
    _removeMarkers();
    _removePolyline();
    stats.dispose();
  }

  void _onSettingsChanged() {
    map.graphicsPreset = settings.liteGraphics
        ? sdk.GraphicsPreset.lite
        : sdk.GraphicsPreset.normal;
    _restartTickTimer();
    if (settings.objectsRevision != _appliedObjectsRevision) {
      unawaited(_rebuildObjects());
    }
  }

  void _restartTickTimer() {
    final period = Duration(microseconds: (1000000 / settings.tickHz).round());
    if (_tickTimer?.isActive == true && _tickPeriod == period) return;
    _tickPeriod = period;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(period, (_) => _onTick());
  }

  Duration? _tickPeriod;

  bool _rebuildInFlight = false;
  bool _rebuildRequested = false;

  /// Пересборка ждёт растеризации иконки, а ручки за это время могут щёлкнуть
  /// ещё раз: без этого две пересборки наложились бы и маркеры удвоились.
  Future<void> _rebuildObjects() async {
    if (_rebuildInFlight) {
      _rebuildRequested = true;
      return;
    }
    _rebuildInFlight = true;
    try {
      do {
        _rebuildRequested = false;
        await _rebuildObjectsOnce();
      } while (_rebuildRequested && !_disposed);
    } finally {
      _rebuildInFlight = false;
    }
  }

  Future<void> _rebuildObjectsOnce() async {
    _appliedObjectsRevision = settings.objectsRevision;
    final track = settings.track == TrackKind.straight
        ? straightTrack
        : serpentineTrack;
    if (!identical(track, _track)) {
      _track = track;
      _trackLength = polylineLengthMeters(track);
      _traveled = 0;
      _segmentFrom = 0;
      _segmentTo = 0;
      _animationStartedAt = null;
    }
    await _ensureIcon();
    if (_disposed) return;
    _removeMarkers();
    _addMarkers();
    _rebuildRoute(fromMeters: _traveled);
  }

  Future<void> _ensureIcon() async {
    final pixels = (settings.iconWidth * devicePixelRatio).round();
    if (_icon != null && pixels == _iconPixels) return;
    final png = await buildCarIconPng(pixels);
    if (_disposed) return;
    _iconPixels = pixels;
    _icon = _loader.loadPngFromByteData(png, pixels, pixels);
  }

  void _addMarkers() {
    final pose = poseAlong(_track, _traveled);
    for (var i = 0; i < settings.markerCount; i++) {
      final point = i == 0
          ? pose.point
          : _ringPoint(pose.point, i, settings.markerCount);
      _markers.add(
        sdk.Marker(
          sdk.MarkerOptions(
            position: _withElevation(point),
            icon: _icon,
            iconWidth: sdk.LogicalPixel(settings.iconWidth),
            iconMapDirection: sdk.MapDirection(pose.bearing),
            zIndex: const sdk.ZIndex(100),
            // Ключевая опция: дефолт SDK — анимировать появление. С ним
            // переукладка иконки видна как полупрозрачность, без него — как
            // пропажа. В бою стоит false.
            animatedAppearance: settings.animatedAppearance,
          ),
        ),
      );
    }
    for (final marker in _markers) {
      _carObjects.addObject(marker);
    }
  }

  void _removeMarkers() {
    for (final marker in _markers) {
      _carObjects.removeObject(marker);
    }
    _markers.clear();
  }

  LatLng _ringPoint(LatLng center, int index, int total) {
    final angle = 2 * math.pi * index / math.max(1, total - 1);
    const metersPerDegreeLat = 111320.0;
    final dLat =
        _extraMarkerRadiusMeters * math.cos(angle) / metersPerDegreeLat;
    final dLon =
        _extraMarkerRadiusMeters *
        math.sin(angle) /
        (metersPerDegreeLat * math.cos(center.lat * math.pi / 180.0));
    return LatLng(center.lat + dLat, center.lon + dLon);
  }

  void _rebuildRoute({required double fromMeters}) {
    _removePolyline();
    if (!settings.routeVisible || _track.length < 2) return;

    // Геометрия начинается от текущей точки машины — каждая пересылка короче
    // предыдущей, ровно как приходит от сервера в бою.
    final tail = _tailFrom(fromMeters);
    if (tail.points.length < 2) return;
    _routePoints = tail.points;
    _routeOffsetMeters = tail.offsetMeters;
    _routeLengthMeters = polylineLengthMeters(tail.points);
    _lastErasedPart = null;
    final polyline = sdk.Polyline(
      sdk.PolylineOptions(
        points: _routePoints.map(_toSdkPoint).toList(),
        width: _routeWidth,
        color: _routeColor,
      ),
    );
    _polyline = polyline;
    _routeObjects.addObject(polyline);
  }

  ({List<LatLng> points, double offsetMeters}) _tailFrom(double meters) {
    var walked = 0.0;
    for (var i = 1; i < _track.length; i++) {
      final segment = haversineMeters(_track[i - 1], _track[i]);
      if (walked + segment > meters) {
        return (points: _track.sublist(i - 1), offsetMeters: walked);
      }
      walked += segment;
    }
    return (points: const <LatLng>[], offsetMeters: walked);
  }

  void _removePolyline() {
    final polyline = _polyline;
    _polyline = null;
    _routePoints = const [];
    _routeLengthMeters = 0;
    if (polyline != null) _routeObjects.removeObject(polyline);
  }

  void _onDriverEvent() {
    if (_track.length < 2) return;
    _segmentFrom = _traveled;
    _segmentTo = _traveled + _metersPerEvent;
    if (_segmentTo >= _trackLength) {
      // Трасса кончилась — начинаем сначала и присылаем полную геометрию.
      _traveled = 0;
      _segmentFrom = 0;
      _segmentTo = _metersPerEvent;
      _rebuildRoute(fromMeters: 0);
    }
    _animationStartedAt = DateTime.now();
    if (settings.followCamera) _moveCamera();
  }

  void _onRouteResend() {
    if (!settings.recreateRoute || !settings.routeVisible) return;
    _rebuildRoute(fromMeters: _traveled);
    _routeRecreates++;
  }

  void _onTick() {
    final startedAt = _animationStartedAt;
    if (startedAt == null || _markers.isEmpty) return;

    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final t = (elapsed / _animationDuration.inMilliseconds).clamp(0.0, 1.0);
    final along = _segmentFrom + (_segmentTo - _segmentFrom) * t;
    final pose = poseAlong(_track, along);
    _traveled = along;

    _writePosition(pose.point);
    _writeDirection(pose.bearing, force: t >= 1.0);
    if (settings.eraseRoute) _writeErasedPart(along, force: t >= 1.0);

    if (t >= 1.0) _animationStartedAt = null;
  }

  void _writePosition(LatLng point) {
    for (var i = 0; i < _markers.length; i++) {
      final target = i == 0 ? point : _ringPoint(point, i, _markers.length);
      _markers[i].position = _withElevation(target);
      _positionWrites++;
    }
  }

  void _writeDirection(double bearing, {required bool force}) {
    if (settings.directionMode == DirectionMode.off) return;
    final now = DateTime.now();
    final interval = settings.directionMode.interval;
    if (!force && interval != null) {
      final last = _lastDirectionWriteAt;
      if (last != null && now.difference(last) < interval) return;
    }
    _lastDirectionWriteAt = now;
    for (final marker in _markers) {
      marker.iconMapDirection = sdk.MapDirection(bearing);
      _directionWrites++;
    }
  }

  void _writeErasedPart(double along, {required bool force}) {
    final polyline = _polyline;
    if (polyline == null || _routeLengthMeters <= 0) return;
    final now = DateTime.now();
    final last = _lastEraseAt;
    if (!force && last != null && now.difference(last) < _eraseInterval) return;
    final part = ((along - _routeOffsetMeters) / _routeLengthMeters).clamp(
      0.0,
      1.0,
    );
    if (_lastErasedPart != null && (part - _lastErasedPart!).abs() < 0.0005) {
      return;
    }
    _lastEraseAt = now;
    _lastErasedPart = part;
    polyline.erasedPart = part;
    _erasedWrites++;
  }

  void _moveCamera() {
    final pose = poseAlong(_track, _segmentTo);
    unawaited(
      map.camera
          .moveToCameraPosition(
            sdk.CameraPosition(
              point: _toSdkPoint(pose.point),
              zoom: const sdk.Zoom(16),
              tilt: const sdk.Tilt(0),
              bearing: const sdk.Bearing(0),
            ),
            _animationDuration,
            sdk.CameraAnimationType.linear,
          )
          .value,
    );
  }

  void _flushStats() {
    stats.value = ReproStats(
      positionWrites: _positionWrites,
      directionWrites: _directionWrites,
      erasedWrites: _erasedWrites,
      routeRecreates: _routeRecreates,
      animating: _animationStartedAt != null,
    );
    _positionWrites = 0;
    _directionWrites = 0;
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
