import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Круглая метка-превью фотографии для карты: снимок в кружке с белым
/// кольцом и тенью. Размер в пикселях картинки; карта сама масштабирует её
/// под плотность экрана.
///
/// Никогда не бросает: если фото не загрузилось (нет сети, файл пропал),
/// рисуется нейтральный кружок. Иначе MapKit получил бы пустую иконку, и метка
/// стала бы невидимой и недоступной для нажатия.
Future<ui.Image> renderPhotoMarkerIcon(ImageProvider source, {int size = 132}) async {
  ui.Image? photo;
  try {
    photo = await _resolve(source).timeout(const Duration(seconds: 15));
  } catch (_) {
    photo = null;
  }

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();
  final center = Offset(s / 2, s / 2);
  const ring = 5.0;
  const shadow = 6.0;
  final radius = s / 2 - shadow;

  // Тень.
  canvas.drawCircle(
    center.translate(0, 2),
    radius,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  // Белое кольцо.
  canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFFFFFFF));

  final inner = radius - ring;
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: inner)));
  if (photo != null) {
    // Центральный квадрат снимка — «cover» для круглой рамки.
    final side = photo.width < photo.height ? photo.width.toDouble() : photo.height.toDouble();
    final src = Rect.fromCenter(
      center: Offset(photo.width / 2, photo.height / 2),
      width: side,
      height: side,
    );
    canvas.drawImageRect(
      photo,
      src,
      Rect.fromCircle(center: center, radius: inner),
      Paint()..filterQuality = FilterQuality.medium,
    );
  } else {
    canvas.drawRect(
      Rect.fromCircle(center: center, radius: inner),
      Paint()..color = const Color(0xFF9E9E9E),
    );
  }
  canvas.restore();

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
    photo?.dispose();
  }
}

Future<ui.Image> _resolve(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
