import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/invite/data/contacts_match.dart';

void main() {
  test('разные записи одного номера дают один хеш', () {
    final variants = [
      '+7 (900) 123-45-67',
      '8 900 123 45 67',
      '89001234567',
      '9001234567',
      '7-900-123-45-67',
    ];
    final hashes = {
      for (final v in variants) hashPhone(normalizePhone(v)!),
    };
    expect(hashes.length, 1);
    expect(normalizePhone('8 900 123 45 67'), '79001234567');
  });

  test('хеш — SHA-256 в hex (64 символа)', () {
    expect(hashPhone('79001234567'), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('короткое и слишком длинное — не номер', () {
    expect(normalizePhone('112'), isNull);
    expect(normalizePhone('abc'), isNull);
    expect(normalizePhone('1234567890123456'), isNull);
  });

  test('иностранный номер сохраняется как есть', () {
    expect(normalizePhone('+44 20 7946 0958'), '442079460958');
  });
}
