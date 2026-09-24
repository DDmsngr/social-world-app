import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/update/update_info.dart';

void main() {
  group('UpdateInfo', () {
    // Ровно та форма, которую пишет шаг «Publish update manifest to Supabase
    // Storage» в .github/workflows/flutter-ci.yml. Если поле переименуют на
    // одной стороне, тест упадёт раньше, чем телефон перестанет видеть версии.
    test('читает манифест из CI', () {
      final json =
          jsonDecode('''
        {
          "versionCode": 42,
          "versionName": "1.0.0",
          "apkUrl": "https://api.example.ru/storage/v1/object/public/app-releases/social-world-42.apk",
          "notes": "Сборка android-release-42"
        }
      ''')
              as Map<String, dynamic>;

      final info = UpdateInfo.fromJson(json);

      expect(info.versionCode, 42);
      expect(info.versionName, '1.0.0');
      expect(info.apkUrl, endsWith('social-world-42.apk'));
      expect(info.notes, 'Сборка android-release-42');
    });

    test('переживает манифест без описания', () {
      final info = UpdateInfo.fromJson({
        'versionCode': 7,
        'apkUrl': 'https://api.example.ru/app.apk',
      });

      expect(info.versionName, isEmpty);
      expect(info.notes, isEmpty);
    });
    group('какой файл качать', () {
      const arm64Phone = 'Dart 3.12 (stable) on "android_arm64"';
      const oldPhone = 'Dart 3.12 (stable) on "android_arm"';

      UpdateInfo info({String? arm64}) => UpdateInfo(
        versionCode: 5071,
        versionName: '1.0.0',
        apkUrl: 'https://x/universal.apk',
        apkUrlArm64: arm64,
        notes: '',
      );

      test('arm64-телефону — лёгкий файл', () {
        expect(
          info(
            arm64: 'https://x/arm64.apk',
          ).urlFor(platformVersion: arm64Phone),
          'https://x/arm64.apk',
        );
      });

      test('другая архитектура — универсальный', () {
        expect(
          info(arm64: 'https://x/arm64.apk').urlFor(platformVersion: oldPhone),
          'https://x/universal.apk',
        );
      });

      test('старый манифест без arm64-ссылки — универсальный для всех', () {
        expect(
          info().urlFor(platformVersion: arm64Phone),
          'https://x/universal.apk',
        );
      });

      test('читает arm64-ссылку из манифеста', () {
        final parsed = UpdateInfo.fromJson({
          'versionCode': 1,
          'apkUrl': 'https://x/u.apk',
          'apkUrlArm64': 'https://x/a.apk',
        });
        expect(parsed.apkUrlArm64, 'https://x/a.apk');
      });
    });
  });
}
