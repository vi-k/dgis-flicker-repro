import 'package:flutter/foundation.dart';

/// Как часто в маркер пишется `iconMapDirection`.
enum DirectionMode {
  everyTick('каждый тик'),
  hz10('10/с'),
  hz5('5/с'),
  off('выкл');

  const DirectionMode(this.label);

  final String label;

  /// null — писать на каждом тике, без ограничения.
  Duration? get interval => switch (this) {
    DirectionMode.everyTick => null,
    DirectionMode.hz10 => const Duration(milliseconds: 100),
    DirectionMode.hz5 => const Duration(milliseconds: 200),
    DirectionMode.off => null,
  };
}

enum TrackKind {
  straight('из тикета'),
  serpentine('змейка');

  const TrackKind(this.label);

  final String label;
}

/// Все ручки прогона. Изменения, требующие пересоздать объекты карты, поднимают
/// [objectsRevision] — сцена сравнивает его со своим и пересобирает маркеры.
class ReproSettings extends ChangeNotifier {
  DirectionMode _directionMode = DirectionMode.everyTick;
  DirectionMode get directionMode => _directionMode;
  set directionMode(DirectionMode value) => _set(() => _directionMode = value);

  bool _animatedAppearance = false;
  bool get animatedAppearance => _animatedAppearance;
  set animatedAppearance(bool value) =>
      _set(() => _animatedAppearance = value, rebuildObjects: true);

  // Маркеров не касается: пересборка объектов сняла бы и добавила заодно
  // машину, и её моргание списали бы на линию.
  bool _routeVisible = true;
  bool get routeVisible => _routeVisible;
  set routeVisible(bool value) => _set(() => _routeVisible = value);

  bool _eraseRoute = true;
  bool get eraseRoute => _eraseRoute;
  set eraseRoute(bool value) => _set(() => _eraseRoute = value);

  /// Держать маркер и полилинию в одном [MapObjectManager] — состояние до
  /// того, как машину вынесли в собственный менеджер. Разделение и есть обход,
  /// которым симптом закрыли на своей стороне; без него дефект должен быть
  /// виден.
  bool _sharedObjectManager = false;
  bool get sharedObjectManager => _sharedObjectManager;
  set sharedObjectManager(bool value) =>
      _set(() => _sharedObjectManager = value, rebuildObjects: true);

  /// Снимать и добавлять полилинию раз в секунду. Отдельно от
  /// [recreateRoute]: там геометрия приходит заново, здесь объект просто
  /// исчезает и появляется — и на слабом железе от этого теряет кадры маркер.
  bool _blinkRoute = false;
  bool get blinkRoute => _blinkRoute;
  set blinkRoute(bool value) => _set(() => _blinkRoute = value);

  bool _recreateRoute = true;
  bool get recreateRoute => _recreateRoute;
  set recreateRoute(bool value) => _set(() => _recreateRoute = value);

  TrackKind _track = TrackKind.serpentine;
  TrackKind get track => _track;
  set track(TrackKind value) => _set(() => _track = value, rebuildObjects: true);

  /// Всего вращаемых маркеров, включая машину.
  int _markerCount = 1;
  int get markerCount => _markerCount;
  set markerCount(int value) =>
      _set(() => _markerCount = value, rebuildObjects: true);

  int _tickHz = 20;
  int get tickHz => _tickHz;
  set tickHz(int value) => _set(() => _tickHz = value);

  double _iconWidth = 63;
  double get iconWidth => _iconWidth;
  set iconWidth(double value) =>
      _set(() => _iconWidth = value, rebuildObjects: true);

  /// Боевой пресет отрисовки — lite. Ручка на случай, если 2GIS попросит
  /// проверить на стандартном.
  bool _liteGraphics = true;
  bool get liteGraphics => _liteGraphics;
  set liteGraphics(bool value) => _set(() => _liteGraphics = value);

  // По умолчанию включена: без неё машина уходит за край экрана за полминуты,
  // и записывать нечего. В поездке QA камера была отключена — тумблер даёт то
  // же условие.
  bool _followCamera = true;
  bool get followCamera => _followCamera;
  set followCamera(bool value) => _set(() => _followCamera = value);

  int _objectsRevision = 0;
  int get objectsRevision => _objectsRevision;

  void _set(VoidCallback change, {bool rebuildObjects = false}) {
    change();
    if (rebuildObjects) _objectsRevision++;
    notifyListeners();
  }
}
