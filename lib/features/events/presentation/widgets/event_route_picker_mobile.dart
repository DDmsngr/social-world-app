import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../../core/config/mapkit_boot.dart';
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
    _objects = window.map.mapObjects.addCollection();
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
                  child: YandexMap(
                    onMapCreated: _onMapCreated,
                    platformViewType: PlatformViewType.Hybrid,
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

class _TapListener implements ymk.MapInputListener {
  void Function(ymk.Point point)? onTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) => onTap?.call(point);

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) {}
}
