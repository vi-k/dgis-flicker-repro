import 'package:flutter/foundation.dart';

/// Частота записи свойства в объект карты. Тик сцены идёт на 60 Гц, поэтому
/// `hz60` — это запись на каждом тике.
enum WriteRate {
  off('выкл', null),
  hz5('5/с', Duration(milliseconds: 200)),
  hz10('10/с', Duration(milliseconds: 100)),
  hz20('20/с', Duration(milliseconds: 50)),
  hz60('60/с', Duration.zero);

  const WriteRate(this.label, this.interval);

  final String label;

  /// `null` — не писать вовсе, `Duration.zero` — писать на каждом тике.
  final Duration? interval;
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
