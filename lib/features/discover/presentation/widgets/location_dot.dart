import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:yandex_maps_mapkit/image.dart' as ymi;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;

/// «Вы здесь»: синяя точка с белым кольцом и мягким ореолом — вместо
/// штатной стрелки MapKit. Кругу направление не нужно: стрелка в движении
/// выглядела как навигатор, а тут нужна просто точка на карте.
const _dotBlue = Color(0xFF2F7BFF);

Future<ui.Image> _renderDot({int size = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();
  final center = Offset(s / 2, s / 2);

  // Ореол.
  canvas.drawCircle(center, s / 2, Paint()..color = _dotBlue.withValues(alpha: 0.22));
  // Тень под кольцом.
  canvas.drawCircle(
    center.translate(0, 1.5),
    s * 0.27,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
  );
  // Белое кольцо и синяя сердцевина.
  canvas.drawCircle(center, s * 0.27, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawCircle(center, s * 0.2, Paint()..color = _dotBlue);

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

/// Подменяет внешний вид слоя геопозиции. Слой держит слушателя слабой
/// ссылкой, поэтому экземпляр обязан жить в поле состояния экрана.
class LocationDotListener implements ymk.UserLocationObjectListener {
  void _apply(ymk.UserLocationView view) {
    final icon = ymi.ImageProvider(() => _renderDot(), id: 'user-location-dot');
    const style = ymk.IconStyle(
      anchor: math.Point(0.5, 0.5),
      scale: 0.55,
      rotationType: ymk.RotationType.NoRotation,
      zIndex: 20,
    );
    view.arrow
      ..setIcon(icon)
      ..setIconStyle(style);
    view.pin
      ..setIcon(icon)
      ..setIconStyle(style);
    view.accuracyCircle
      ..fillColor = _dotBlue.withValues(alpha: 0.10)
      ..strokeColor = _dotBlue.withValues(alpha: 0.25)
      ..strokeWidth = 1;
  }

  @override
  void onObjectAdded(ymk.UserLocationView view) => _apply(view);

  @override
  void onObjectRemoved(ymk.UserLocationView view) {}

  @override
  void onObjectUpdated(ymk.UserLocationView view, ymk.ObjectEvent event) {
    // Смена «стрелка/булавка» сбрасывает иконки — возвращаем свою.
    if (event is ymk.UserLocationIconChanged) _apply(view);
  }
}
