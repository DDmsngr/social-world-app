import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../routes/presentation/widgets/route_photo_icon.dart';

/// Метка квеста на Pulse: круг с фото квеста (или флажком, если фото нет) в
/// акцентном кольце и пилюля «занято/мест» под ним. Завершённый квест (след
/// на сутки) — серое кольцо и без пилюли.
///
/// Никогда не бросает: не загрузилось фото — рисуется флажок, иначе метка
/// стала бы невидимой и недоступной для нажатия.
Future<ui.Image> renderQuestMarker({
  ImageProvider? photo,
  String? badge,
  bool trail = false,
  Color accent = const Color(0xFFEA2249),
}) async {
  ui.Image? image;
  if (photo != null) {
    try {
      image = await resolveUiImage(photo).timeout(const Duration(seconds: 12));
    } catch (_) {
      image = null;
    }
  }

  const width = 132.0;
  const height = 176.0;
  const circleCenter = Offset(width / 2, 66);
  const radius = 58.0;
  const ring = 8.0;
  final ringColor = trail ? const Color(0xFF8A8B90) : accent;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  // Тень под кругом.
  canvas.drawCircle(
    circleCenter.translate(0, 3),
    radius,
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  // Кольцо.
  canvas.drawCircle(circleCenter, radius, Paint()..color = ringColor);
  // Белая окантовка внутри кольца отделяет фото от цвета.
  canvas.drawCircle(circleCenter, radius - ring, Paint()..color = Colors.white);
  final inner = radius - ring - 3;
  final innerRect = Rect.fromCircle(center: circleCenter, radius: inner);

  canvas.save();
  canvas.clipPath(Path()..addOval(innerRect));
  if (image != null) {
    final side = image.width < image.height ? image.width.toDouble() : image.height.toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromCenter(
        center: Offset(image.width / 2, image.height / 2),
        width: side,
        height: side,
      ),
      innerRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  } else {
    canvas.drawRect(innerRect, Paint()..color = ringColor);
    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.flag.codePoint),
        style: TextStyle(
          fontFamily: Icons.flag.fontFamily,
          package: Icons.flag.fontPackage,
          fontSize: 68,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(
      canvas,
      circleCenter - Offset(glyph.width / 2, glyph.height / 2),
    );
  }
  canvas.restore();

  // Пилюля «0/8».
  if (badge != null && !trail) {
    final text = TextPainter(
      text: TextSpan(
        text: badge,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111111),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillW = text.width + 30;
    const pillH = 40.0;
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(width / 2, 140), width: pillW, height: pillH),
      const Radius.circular(pillH / 2),
    );
    canvas.drawRRect(
      pill.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(pill, Paint()..color = Colors.white);
    canvas.drawRRect(
      pill,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ringColor,
    );
    text.paint(canvas, pill.center - Offset(text.width / 2, text.height / 2));
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width.toInt(), height.toInt());
  } finally {
    picture.dispose();
    image?.dispose();
  }
}
