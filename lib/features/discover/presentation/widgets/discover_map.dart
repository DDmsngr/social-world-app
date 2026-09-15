// Web не компилирует yandex_mapkit, поэтому платформенный импорт отделён.
export 'discover_map_stub.dart' if (dart.library.io) 'discover_map_mobile.dart';
