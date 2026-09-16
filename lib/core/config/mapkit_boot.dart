// Web не компилирует yandex_maps_mapkit, поэтому инициализация разделена
// по платформам тем же приёмом, что и сам виджет карты.
export 'mapkit_boot_stub.dart'
    if (dart.library.io) 'mapkit_boot_native.dart';
