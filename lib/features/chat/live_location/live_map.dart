// Web не компилирует yandex_maps_mapkit — тот же приём, что у карты маршрута.
export 'live_map_stub.dart' if (dart.library.io) 'live_map_mobile.dart';
export 'live_map_marker.dart';
