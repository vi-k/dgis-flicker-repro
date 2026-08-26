import 'package:flutter/foundation.dart';

/// Частота записи свойства в объект карты. У каждой записи собственный таймер,
/// поэтому частота точная: привязка к тику сцены округляла бы её до кратной
/// шестнадцати миллисекундам.
enum WriteRate {
  off('выкл', null),
  hz5('5/с', 5),
  hz10('10/с', 10),
  hz20('20/с', 20),
  hz30('30/с', 30),
  hz40('40/с', 40),
  hz50('50/с', 50),
  hz60('60/с', 60);

  const WriteRate(this.label, this.hz);

  final String label;

  /// `null` — не писать вовсе.
  final int? hz;

  Duration? get period =>
      hz == null ? null : Duration(microseconds: (1000000 / hz!).round());
}

/// Ровно две ручки: как часто пишется направление в маркер и доля съеденного в
/// полилинию. Остальное закреплено на значениях приложения, где симптом
/// наблюдался, — иначе в прогоне меняется больше одного параметра.
class ReproSettings extends ChangeNotifier {
  WriteRate _direction = WriteRate.hz60;
  WriteRate get direction => _direction;
  set direction(WriteRate value) {
    if (value == _direction) return;
    _direction = value;
    notifyListeners();
  }

  WriteRate _erased = WriteRate.hz60;
  WriteRate get erased => _erased;
  set erased(WriteRate value) {
    if (value == _erased) return;
    _erased = value;
    notifyListeners();
  }
}
