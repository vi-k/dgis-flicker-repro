import 'dart:typed_data';
import 'dart:ui' as ui;

/// Иконка рисуется в рантайме: в репозитории нет ни одного бинарного ассета,
/// а чёрный силуэт остаётся единственным крупным тёмным объектом на светлой
/// карте — по нему и считаются кадры (tools/darkcount.py).
///
/// Размер в пикселях обязан совпадать с объявленным в [sdk.ImageData]: SDK не
/// ресемплирует растр под другой размер, а режет или растягивает его.
Future<ByteData> buildCarIconPng(int sizePixels) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = sizePixels.toDouble();
  final paint = ui.Paint()..color = const ui.Color(0xFF000000);

  // Стрелка носом вверх: направление 0° у SDK — на север.
  final body = ui.Path()
    ..moveTo(s * 0.50, s * 0.04)
    ..lineTo(s * 0.92, s * 0.78)
    ..lineTo(s * 0.50, s * 0.60)
    ..lineTo(s * 0.08, s * 0.78)
    ..close();
  canvas.drawPath(body, paint);

  final picture = recorder.endRecording();
  final image = await picture.toImage(sizePixels, sizePixels);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}
