import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Ключи бэкенда лежат в `.env` (в гите его нет, есть только `.env.example`).
///
/// Пока self-hosted Supabase не поднят на Yandex Cloud, приложение
/// запускается без бэкенда: [isConfigured] = false, UI работает на заглушках.
abstract final class Env {
  static const _urlKey = 'SUPABASE_URL';
  static const _anonKey = 'SUPABASE_ANON_KEY';
  static const _yandexMapkitKey = 'YANDEX_MAPKIT_API_KEY';

  static bool _loaded = false;

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
      _loaded = true;
    } catch (_) {
      // Файла нет — работаем в offline-режиме, это штатный сценарий на старте.
      _loaded = false;
    }
  }

  static String get supabaseUrl => _read(_urlKey);
  static String get supabaseAnonKey => _read(_anonKey);
  static String get yandexMapkitApiKey => _read(_yandexMapkitKey);

  static bool get isConfigured =>
      _loaded && _read(_urlKey).isNotEmpty && _read(_anonKey).isNotEmpty;

  static String _read(String key) => _loaded ? (dotenv.env[key] ?? '') : '';
}
