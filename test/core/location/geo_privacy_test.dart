import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/location/geo_privacy.dart';

/// Расстояние между точками по сфере — для проверки, что размытие
/// не уводит человека дальше обещанного радиуса.
double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * math.pi / 180;

  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(a));
}

void main() {
  // Театральная площадь в Сочи.
  const lat = 43.5789;
  const lng = 39.7232;

  group('GeoPrivacy.blur', () {
    test('не уводит дальше радиуса размытия', () {
      for (final radius in GeoPrivacy.radiusOptions) {
        for (var i = 0; i < 200; i++) {
          final testLat = lat + (i - 100) * 0.0004;
          final testLng = lng + (i - 100) * 0.0006;
          final point = GeoPrivacy.blur(
            latitude: testLat,
            longitude: testLng,
            salt: 'user-$i',
            radiusMeters: radius,
          );
          final distance = _metersBetween(
            testLat,
            testLng,
            point.latitude,
            point.longitude,
          );
          expect(
            distance,
            lessThanOrEqualTo(radius),
            reason: 'radius $radius, шаг $i: ушли на $distance м',
          );
        }
      }
    });

    test('для одной точки и одной соли результат стабилен', () {
      final first = GeoPrivacy.blur(latitude: lat, longitude: lng, salt: 'abc');
      final second = GeoPrivacy.blur(latitude: lat, longitude: lng, salt: 'abc');

      expect(first.latitude, second.latitude);
      expect(first.longitude, second.longitude);
    });

    test('разные соли дают разную сетку', () {
      final a = GeoPrivacy.blur(latitude: lat, longitude: lng, salt: 'user-a');
      final b = GeoPrivacy.blur(latitude: lat, longitude: lng, salt: 'user-b');

      expect(a.latitude == b.latitude && a.longitude == b.longitude, isFalse);
    });

    test('точные координаты наружу не уходят', () {
      final point = GeoPrivacy.blur(latitude: lat, longitude: lng, salt: 'x');

      expect(point.latitude, isNot(lat));
      expect(point.longitude, isNot(lng));
      expect(point.toJson().keys, containsAll(['latitude', 'longitude', 'blur_radius_m']));
    });

    test('около полюса не разваливается', () {
      final point = GeoPrivacy.blur(
        latitude: 89.99,
        longitude: 179.99,
        salt: 'polar',
        radiusMeters: 1000,
      );

      expect(point.latitude, inInclusiveRange(-90, 90));
      expect(point.longitude, inInclusiveRange(-180, 180));
    });
  });
}
