// Web не компилирует yandex_maps_mapkit — тот же приём, что у карты в Discover.
export 'route_map_stub.dart' if (dart.library.io) 'route_map_mobile.dart';
