import 'dart:typed_data';

/// Убирает из JPEG метаданные (GPS, модель телефона, время съёмки, XMP, IPTC),
/// не перекодируя картинку: пиксели остаются байт в байт.
///
/// Единственное, что сохраняется, — ориентация (тег 0x0112): без неё снимок,
/// сделанный боком, лёг бы набок. Не-JPEG возвращается без изменений.
Uint8List stripJpegMetadata(Uint8List data) {
  if (data.length < 4 || data[0] != 0xFF || data[1] != 0xD8) return data;

  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  int? orientation;
  var i = 2;

  while (i + 4 <= data.length) {
    if (data[i] != 0xFF) break;
    final marker = data[i + 1];
    // Заполнитель 0xFF перед маркером.
    if (marker == 0xFF) {
      i++;
      continue;
    }
    // Начало сканирования: дальше идут сами пиксели до конца файла.
    if (marker == 0xDA) break;
    // Маркеры без длины.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      out.add(data.sublist(i, i + 2));
      i += 2;
      continue;
    }
    final length = (data[i + 2] << 8) | data[i + 3];
    final end = i + 2 + length;
    if (length < 2 || end > data.length) return data;

    // APP1 (Exif, XMP) … APP15 и комментарии — метаданные.
    final isMeta =
        marker == 0xFE || (marker >= 0xE1 && marker <= 0xEF);
    if (isMeta) {
      if (marker == 0xE1) orientation ??= _exifOrientation(data, i + 4, end);
    } else {
      out.add(data.sublist(i, end));
    }
    i = end;
  }

  final rest = data.sublist(i);
  final head = out.takeBytes();
  final builder = BytesBuilder(copy: false)..add(head.sublist(0, 2));
  if (orientation != null && orientation > 1 && orientation <= 8) {
    builder.add(_orientationSegment(orientation));
  }
  builder
    ..add(head.sublist(2))
    ..add(rest);
  return builder.takeBytes();
}

/// Ориентация из Exif-сегмента (данные с [start] до [end]) или null.
int? _exifOrientation(Uint8List d, int start, int end) {
  // «Exif\0\0» + TIFF-заголовок (8 байт) + число записей (2 байта).
  if (end - start < 6 + 10) return null;
  const exif = [0x45, 0x78, 0x69, 0x66, 0, 0];
  for (var k = 0; k < 6; k++) {
    if (d[start + k] != exif[k]) return null;
  }
  final tiff = start + 6;
  final little = d[tiff] == 0x49 && d[tiff + 1] == 0x49;
  final big = d[tiff] == 0x4D && d[tiff + 1] == 0x4D;
  if (!little && !big) return null;

  int u16(int at) => little
      ? d[at] | (d[at + 1] << 8)
      : (d[at] << 8) | d[at + 1];
  int u32(int at) => little
      ? d[at] | (d[at + 1] << 8) | (d[at + 2] << 16) | (d[at + 3] << 24)
      : (d[at] << 24) | (d[at + 1] << 16) | (d[at + 2] << 8) | d[at + 3];

  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > end) return null;
  final count = u16(ifd);
  for (var n = 0; n < count; n++) {
    final entry = ifd + 2 + n * 12;
    if (entry + 12 > end) return null;
    if (u16(entry) == 0x0112) return u16(entry + 8);
  }
  return null;
}

/// Минимальный Exif-сегмент, в котором есть только ориентация.
Uint8List _orientationSegment(int orientation) {
  return Uint8List.fromList([
    0xFF, 0xE1, 0x00, 0x22, // APP1, длина 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // «Exif»
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // TIFF, big-endian
    0x00, 0x01, // одна запись
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // ориентация, SHORT, 1
    0x00, orientation, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // следующего IFD нет
  ]);
}
