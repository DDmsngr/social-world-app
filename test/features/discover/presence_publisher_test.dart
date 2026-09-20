import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/discover/presentation/providers/presence_publisher.dart';

const _user = AppUser(id: 'user-1', displayName: 'Алексей', locationBlurM: 500);

// Точка в центре Сочи — реальные координаты, чтобы проверять смещение в метрах.
const _lat = 43.5789;
const _lng = 39.7232;

void main() {
  group('blurredPresenceFor', () {
    test('точные координаты наружу не уходят', () {
      final point = blurredPresenceFor(
        enabled: true,
        user: _user,
        latitude: _lat,
        longitude: _lng,
      )!;

      expect(point.latitude, isNot(_lat));
      expect(point.longitude, isNot(_lng));
      // Но и не в другом городе: смещение в пределах ячейки размытия.
      expect((point.latitude - _lat).abs(), lessThan(0.01));
      expect((point.longitude - _lng).abs(), lessThan(0.02));
    });

    test('радиус берётся из настроек человека, а не из умолчания', () {
      final point = blurredPresenceFor(
        enabled: true,
        user: const AppUser(id: 'user-1', locationBlurM: 3000),
        latitude: _lat,
        longitude: _lng,
      )!;

      expect(point.radiusMeters, 3000);
    });

    test('выключенное присутствие не публикуется', () {
      expect(
        blurredPresenceFor(
          enabled: false,
          user: _user,
          latitude: _lat,
          longitude: _lng,
        ),
        isNull,
      );
    });

    test('без сессии публиковать нечего', () {
      expect(
        blurredPresenceFor(
          enabled: true,
          user: null,
          latitude: _lat,
          longitude: _lng,
        ),
        isNull,
      );
    });

    test('без координат публиковать нечего', () {
      expect(
        blurredPresenceFor(
          enabled: true,
          user: _user,
          latitude: null,
          longitude: null,
        ),
        isNull,
      );
    });

    test('у разных людей одна точка размывается по-разному', () {
      final mine = blurredPresenceFor(
        enabled: true,
        user: _user,
        latitude: _lat,
        longitude: _lng,
      )!;
      final theirs = blurredPresenceFor(
        enabled: true,
        user: const AppUser(id: 'user-2', locationBlurM: 500),
        latitude: _lat,
        longitude: _lng,
      )!;

      // Сетка у каждого своя (соль — id), иначе по общим границам ячеек её
      // можно было бы восстановить и вычислить точное положение.
      expect(
        mine.latitude == theirs.latitude && mine.longitude == theirs.longitude,
        isFalse,
      );
    });

    test('одна и та же точка у одного человека стабильна', () {
      BlurredPointSnapshot snapshot() {
        final point = blurredPresenceFor(
          enabled: true,
          user: _user,
          latitude: _lat,
          longitude: _lng,
        )!;
        return (point.latitude, point.longitude);
      }

      // Иначе пятно дёргалось бы по карте при каждом обновлении.
      expect(snapshot(), snapshot());
    });
  });
}

typedef BlurredPointSnapshot = (double, double);
