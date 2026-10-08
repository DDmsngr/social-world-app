import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/domain/repositories/auth_repository.dart';
import 'package:social_world/features/discover/domain/entities/city.dart';

void main() {
  group('Username', () {
    test('ник приводится к хранимому виду', () {
      expect(Username.normalize('  @Alex_99 '), 'alex_99');
    });

    test('пустой ник допустим — он необязателен', () {
      expect(Username.validate(''), isNull);
      expect(Username.validate('@'), isNull);
    });

    test('правила формата', () {
      expect(Username.validate('ab'), 'Минимум 3 знака');
      expect(Username.validate('a' * 21), 'Максимум 20 знаков');
      expect(Username.validate('ник'), 'Только латиница, цифры и _');
      expect(Username.validate('alex.k'), 'Только латиница, цифры и _');
      expect(Username.validate('@Alex_99'), isNull);
    });
  });

  group('Cities.byName', () {
    test('находит город из профиля без учёта регистра', () {
      expect(Cities.byName('москва')?.id, 'moscow');
      expect(Cities.byName(' Сочи ')?.id, 'sochi');
    });

    test('неизвестный или пустой — null, без подстановки Сочи', () {
      expect(Cities.byName('Тмутаракань'), isNull);
      expect(Cities.byName(null), isNull);
      expect(Cities.byName(''), isNull);
    });
  });

  group('AppUser.hasProfile', () {
    test('имя от VK без пройденного знакомства — онбординг нужен', () {
      const user = AppUser(id: 'u', displayName: 'Семён', onboarded: false);
      expect(user.hasProfile, isFalse);
    });

    test('имя и пройденное знакомство — профиль заполнен', () {
      const user = AppUser(id: 'u', displayName: 'Семён');
      expect(user.hasProfile, isTrue);
    });

    test('без имени онбординг нужен всегда', () {
      const user = AppUser(id: 'u');
      expect(user.hasProfile, isFalse);
    });
  });
}
