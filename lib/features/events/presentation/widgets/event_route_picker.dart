// Web не компилирует yandex_maps_mapkit — тот же приём, что у карты в Discover.
export 'event_route_picker_stub.dart'
    if (dart.library.io) 'event_route_picker_mobile.dart';
