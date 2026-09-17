import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/update/update_info.dart';

void main() {
  group('UpdateInfo', () {
    // Ровно та форма, которую пишет шаг «Publish update manifest to Supabase
    // Storage» в .github/workflows/flutter-ci.yml. Если поле переименуют на
    // одной стороне, тест упадёт раньше, чем телефон перестанет видеть версии.
    test('читает манифест из CI', () {
      final json = jsonDecode('''
        {
          "versionCode": 42,
          "versionName": "1.0.0",
          "apkUrl": "https://api.example.ru/storage/v1/object/public/app-releases/social-world-42.apk",
          "notes": "Сборка android-release-42"
        }
      ''') as Map<String, dynamic>;

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
  });
}
