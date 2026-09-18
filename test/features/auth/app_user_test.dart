import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';

void main() {
  group('AppUser.displayContact', () {
    // Регрессия: мост VK/Яндекс заводит служебный email вида
    // vk.<external_id>@id.socialworld.internal — это не контакт человека,
    // а обёртка над его внешним аккаунтом, и профиль не должен его показывать.
    test('прячет синтетический email моста VK/Яндекс', () {
      const user = AppUser(
        id: 'u1',
        email: 'vk.123456789@id.socialworld.internal',
      );

      expect(user.hasSyntheticEmail, isTrue);
      expect(user.displayContact, isNull);
    });

    test('показывает настоящий email', () {
      const user = AppUser(id: 'u1', email: 'alex@example.com');

      expect(user.hasSyntheticEmail, isFalse);
      expect(user.displayContact, 'alex@example.com');
    });

    test('без email показывает телефон', () {
      const user = AppUser(id: 'u1', phone: '+79990001122');

      expect(user.displayContact, '+79990001122');
    });

    test('ни email, ни телефона — ничего не показываем', () {
      const user = AppUser(id: 'u1');

      expect(user.displayContact, isNull);
    });
  });
}
