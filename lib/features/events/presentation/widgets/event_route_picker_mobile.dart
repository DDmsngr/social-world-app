import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/search.dart' as ysearch;
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../../core/config/mapkit_boot.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/location/device_position.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_message.dart';
import '../../domain/entities/event_route.dart';

/// Выбор точек маршрута прямо на карте: каждое нажатие добавляет следующую
/// точку, между точками рисуется линия. Автоматической прокладки по дорогам
/// нет — это следующий этап; сейчас маршрут — это последовательность точек.
class EventRoutePickerScreen extends StatefulWidget {
  const EventRoutePickerScreen({
    super.key,
    required this.initial,
    required this.centerLatitude,
    required this.centerLongitude,
  });

  final List<EventRoutePoint> initial;
  final double centerLatitude;
  final double centerLongitude;

  @override
  State<EventRoutePickerScreen> createState() => _EventRoutePickerScreenState();
}

class _EventRoutePickerScreenState extends State<EventRoutePickerScreen> {
  late final AppLifecycleListener _lifecycle;
  late final List<EventRoutePoint> _points = List.of(widget.initial);
  final _tapListener = _TapListener();

  ymk.MapObjectCollection? _objects;
  bool _mapkitRunning = false;

  ymk.MapWindow? _window;

  /// Отдельный слой под «я здесь»: [_redraw] чистит только точки маршрута.
  ymk.MapObjectCollection? _me;

  // Поиск по картам Яндекса: названия мест и адреса, как в приложении «Карты».
  final _query = TextEditingController();
  var _results = <_Hit>[];
  var _searching = false;
  String? _searchNote;
  var _searchTicket = 0;

  @override
  void initState() {
    super.initState();
    _startMapkit();
    _lifecycle = AppLifecycleListener(
      onResume: _startMapkit,
      onInactive: _stopMapkit,
    );
    _tapListener.onTap = _addPoint;
  }

  @override
  void dispose() {
    _stopMapkit();
    _lifecycle.dispose();
    _query.dispose();
    super.dispose();
  }

  void _startMapkit() {
    if (_mapkitRunning) return;
    _mapkitRunning = true;
    mapkit.onStart();
  }

  void _stopMapkit() {
    if (!_mapkitRunning) return;
    _mapkitRunning = false;
    mapkit.onStop();
  }

  void _onMapCreated(ymk.MapWindow window) {
    window.map.nightModeEnabled = AppColors.current.isDark;
    _window = window;
    _objects = window.map.mapObjects.addCollection();
    _me = window.map.mapObjects.addCollection();
    window.map.addInputListener(_tapListener);

    final anchor = _points.isNotEmpty
        ? ymk.Point(
            latitude: _points.first.latitude,
            longitude: _points.first.longitude,
          )
        : ymk.Point(
            latitude: widget.centerLatitude,
            longitude: widget.centerLongitude,
          );
    window.map.move(ymk.CameraPosition(anchor, zoom: 14, azimuth: 0, tilt: 0));
    _redraw();
    _showMe(moveCamera: false, ask: false);
  }

  /// Моё положение: синяя точка с белой каймой. Нужно, чтобы поставить метку
  /// рядом с собой. [ask] — разрешено ли спрашивать доступ к геолокации (при
  /// открытии экрана не спрашиваем, только если он уже выдан).
  Future<void> _showMe({required bool moveCamera, required bool ask}) async {
    if (!ask && !await hasLocationPermission()) return;
    if (!mounted) return;
    final result = await requestDevicePosition(context);
    final position = result.position;
    if (!mounted) return;
    if (position == null) {
      final message = result.message;
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    final here = ymk.Point(latitude: position.latitude, longitude: position.longitude);
    final collection = _me;
    if (collection != null) {
      collection.clear();
      collection.addCircle(ymk.Circle(here, radius: 14))
        ..fillColor = const Color(0xFF2E7DF6)
        ..strokeColor = const Color(0xFFFFFFFF)
        ..strokeWidth = 3;
    }
    if (moveCamera) {
      _window?.map.move(
        ymk.CameraPosition(here, zoom: 16, azimuth: 0, tilt: 0),
        animation: const ymk.Animation(type: ymk.AnimationType.Smooth, duration: 0.4),
      );
    }
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    final window = _window;
    if (text.isEmpty || window == null) return;
    FocusScope.of(context).unfocus();
    final ticket = ++_searchTicket;
    setState(() {
      _searching = true;
      _searchNote = null;
      _results = [];
    });
    void fail(Object error) {
      AppLog.add('Поиск на карте: $error');
      if (!mounted || ticket != _searchTicket) return;
      setState(() {
        _searching = false;
        _searchNote = 'Поиск не сработал, попробуйте ещё раз';
      });
    }

    try {
      // Ищем рядом с тем, что сейчас на экране: «кофейня» должна найтись здесь,
      // а не на другом конце страны.
      final target = window.map.cameraPosition.target;
      final box = ymk.BoundingBox(
        ymk.Point(latitude: target.latitude - 0.25, longitude: target.longitude - 0.4),
        ymk.Point(latitude: target.latitude + 0.25, longitude: target.longitude + 0.4),
      );
      final manager = ysearch.SearchFactory.instance.createSearchManager(
        ysearch.SearchManagerType.Combined,
      );
      manager.submit(
        ymk.Geometry.fromBoundingBox(box),
        ysearch.SearchOptions(
          searchTypes: ysearch.SearchType.Geo | ysearch.SearchType.Biz,
          resultPageSize: 8,
        ),
        ysearch.SearchSessionSearchListener(
          onSearchResponse: (response) {
            if (!mounted || ticket != _searchTicket) return;
            final hits = <_Hit>[];
            for (final item in response.collection.children) {
              final object = item.asGeoObject();
              if (object == null) continue;
              for (final geometry in object.geometry) {
                final point = geometry.asPoint();
                if (point == null) continue;
                hits.add(
                  _Hit(
                    object.name ?? 'Место',
                    object.descriptionText,
                    point.latitude,
                    point.longitude,
                  ),
                );
                break;
              }
            }
            setState(() {
              _searching = false;
              _results = hits;
              _searchNote = hits.isEmpty ? 'Ничего не найдено' : null;
            });
          },
          onSearchError: fail,
        ),
        text: text,
      );
    } catch (error) {
      fail(error);
    }
  }

  void _pickHit(_Hit hit) {
    setState(() => _results = []);
    _window?.map.move(
      ymk.CameraPosition(
        ymk.Point(latitude: hit.latitude, longitude: hit.longitude),
        zoom: 17,
        azimuth: 0,
        tilt: 0,
      ),
      animation: const ymk.Animation(type: ymk.AnimationType.Smooth, duration: 0.4),
    );
    if (_points.length >= maxEventRoutePoints) return;
    // Название найденного места едет вместе с точкой: так его увидят другие.
    setState(() {
      _points.add(
        EventRoutePoint(latitude: hit.latitude, longitude: hit.longitude, title: hit.title),
      );
    });
    _redraw();
  }

  void _addPoint(ymk.Point point) {
    if (_points.length >= maxEventRoutePoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не больше $maxEventRoutePoints точек')),
      );
      return;
    }
    setState(() {
      _points.add(
        EventRoutePoint(latitude: point.latitude, longitude: point.longitude),
      );
    });
    _redraw();
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(_points.removeLast);
    _redraw();
  }

  void _clear() {
    setState(_points.clear);
    _redraw();
  }

  void _redraw() {
    final collection = _objects;
    if (collection == null) return;
    collection.clear();

    final line = [
      for (final point in _points)
        ymk.Point(latitude: point.latitude, longitude: point.longitude),
    ];

    if (line.length >= 2) {
      collection.addPolylineWithGeometry(ymk.Polyline(line))
        ..style = ymk.LineStyle(
          strokeWidth: 4,
          outlineWidth: 1,
          outlineColor: AppColors.ink,
        )
        ..setStrokeColor(AppColors.primaryTint);
    }

    for (var index = 0; index < line.length; index++) {
      collection.addPlacemarkWithPoint(line[index])
        ..setText('${index + 1}')
        ..setTextStyle(
          ymk.TextStyle(
            size: 13,
            color: AppColors.text,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Bottom,
            offset: 8,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = !(Platform.isAndroid || Platform.isIOS)
        ? 'Карта доступна на Android и iOS'
        : !MapkitBoot.isReady
        ? 'Карта не запустилась: ${MapkitBoot.status}'
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут на карте')),
      body: unavailable != null
          ? StateMessage(title: unavailable, icon: Icons.map_outlined)
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      YandexMap(
                        onMapCreated: _onMapCreated,
                        platformViewType: PlatformViewType.Hybrid,
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 10,
                        child: _SearchBox(
                          controller: _query,
                          searching: _searching,
                          note: _searchNote,
                          results: _results,
                          onSubmit: _search,
                          onPick: _pickHit,
                          onClear: () => setState(() {
                            _query.clear();
                            _results = [];
                            _searchNote = null;
                            _searchTicket++;
                            _searching = false;
                          }),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'route-picker-me',
                          onPressed: () => _showMe(moveCamera: true, ask: true),
                          tooltip: 'Где я',
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ],
                  ),
                ),
                _Panel(
                  count: _points.length,
                  onUndo: _points.isEmpty ? null : _undo,
                  onClear: _points.isEmpty ? null : _clear,
                  onDone: () => Navigator.of(context).pop(_points),
                ),
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.count,
    required this.onUndo,
    required this.onClear,
    required this.onDone,
  });

  final int count;
  final VoidCallback? onUndo;
  final VoidCallback? onClear;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink2,
        border: Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          12,
          AppSpacing.gutter,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 0
                  ? 'Нажимайте на карту — точки встанут по порядку'
                  : 'Точек: $count. Нажмите ещё, чтобы продолжить маршрут',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  onPressed: onUndo,
                  child: const Text('Отменить последнюю'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onClear, child: const Text('Очистить')),
                const Spacer(),
                FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: const Text('Готово'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Найденное на картах место: название, адрес и точка.
class _Hit {
  const _Hit(this.title, this.subtitle, this.latitude, this.longitude);

  final String title;
  final String? subtitle;
  final double latitude;
  final double longitude;
}

/// Поле поиска поверх карты. Результаты выпадают списком под ним.
class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.searching,
    required this.note,
    required this.results,
    required this.onSubmit,
    required this.onPick,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool searching;
  final String? note;
  final List<_Hit> results;
  final VoidCallback onSubmit;
  final ValueChanged<_Hit> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.ink2,
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Найти место или адрес',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (_, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              onPressed: onClear,
                              tooltip: 'Очистить поиск',
                              icon: const Icon(Icons.close),
                            ),
                    ),
              border: InputBorder.none,
            ),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: AppColors.ink2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(note!, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
          ),
        if (results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: AppColors.ink2,
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: results.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.hair),
                  itemBuilder: (_, index) {
                    final hit = results[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.place_outlined, color: AppColors.primaryTint),
                      title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: hit.subtitle == null
                          ? null
                          : Text(hit.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => onPick(hit),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TapListener implements ymk.MapInputListener {
  void Function(ymk.Point point)? onTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) => onTap?.call(point);

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) {}
}
