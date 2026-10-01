import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/media/exif_strip.dart';

Uint8List _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    marker,
    length >> 8,
    length & 0xFF,
    ...payload,
  ]);
}

/// Exif с GPS-подобным мусором и ориентацией [orientation] (little-endian).
Uint8List _exif(int orientation) {
  final tiff = <int>[
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // II, IFD0 по смещению 8
    0x02, 0x00, // две записи
    0x0F, 0x01, 0x02, 0x00, 0x04, 0x00, 0x00, 0x00, 0x47, 0x50, 0x53, 0x00, //
    0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, orientation, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
  ];
  return _segment(0xE1, [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff]);
}

Uint8List _jpeg(List<Uint8List> segments) => Uint8List.fromList([
  0xFF,
  0xD8,
  for (final s in segments) ...s,
  ..._segment(0xDB, [1, 2, 3]),
  0xFF, 0xDA, 0x00, 0x03, 0x00, // начало сканирования
  0x12, 0x34, 0xFF, 0xD9,
]);

bool _contains(Uint8List data, List<int> needle) {
  for (var i = 0; i + needle.length <= data.length; i++) {
    var ok = true;
    for (var k = 0; k < needle.length; k++) {
      if (data[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  test('убирает Exif, XMP и комментарии, пиксели не трогает', () {
    final input = _jpeg([
      _exif(1),
      _segment(0xE1, [...'http://ns.adobe.com/xap/1.0/\u0000'.codeUnits, 1]),
      _segment(0xFE, 'comment'.codeUnits),
    ]);
    final out = stripJpegMetadata(input);

    expect(_contains(out, 'GPS'.codeUnits), isFalse);
    expect(_contains(out, 'Exif'.codeUnits), isFalse);
    expect(_contains(out, 'adobe'.codeUnits), isFalse);
    expect(_contains(out, 'comment'.codeUnits), isFalse);
    // Таблица квантования и сами данные остались.
    expect(_contains(out, [0xFF, 0xDB, 0x00, 0x05, 1, 2, 3]), isTrue);
    expect(out.sublist(out.length - 5), [0x00, 0x12, 0x34, 0xFF, 0xD9]);
    expect(out.sublist(0, 2), [0xFF, 0xD8]);
  });

  test('ориентацию оставляет, остальное из Exif — нет', () {
    final out = stripJpegMetadata(_jpeg([_exif(6)]));

    expect(_contains(out, 'GPS'.codeUnits), isFalse);
    // Минимальный Exif: big-endian, тег 0x0112 со значением 6.
    expect(
      _contains(out, [0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 6]),
      isTrue,
    );
    // Не длиннее исходного.
    expect(out.length, lessThan(_jpeg([_exif(6)]).length));
  });

  test('не JPEG возвращается как есть', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
    expect(stripJpegMetadata(png), same(png));
  });

  test('битый сегмент — исходные байты, без падения', () {
    final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 1]);
    expect(stripJpegMetadata(broken), same(broken));
  });
}
