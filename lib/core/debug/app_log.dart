import 'dart:collection';

/// Лог в памяти для отладки на устройстве без adb/logcat — телефон
/// тестировщика не всегда подключён к компьютеру. Ловит то, что видно
/// из Dart: статус MapKit, ошибки Flutter и ручную проверку сети.
/// Нативные ошибки самого MapKit SDK (например, отказ тайл-сервера) сюда
/// не попадают — тех логов без adb не получить в принципе.
abstract final class AppLog {
  static const _maxEntries = 300;
  static final _entries = Queue<String>();

  static List<String> get entries => List.unmodifiable(_entries);

  static void add(String message) {
    final time = DateTime.now().toIso8601String().substring(11, 23);
    _entries.addFirst('$time  $message');
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
  }

  static void clear() => _entries.clear();
}
