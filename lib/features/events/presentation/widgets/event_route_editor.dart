import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../data/address_resolver.dart';
import '../../domain/entities/event_route.dart';
import 'event_route_picker.dart';

/// Сборка маршрута события двумя способами: по адресам («ввёл, нажал +») и на
/// карте. Обе дороги ведут в один и тот же список точек, порядок можно менять
/// перетаскиванием.
class EventRouteEditor extends StatefulWidget {
  const EventRouteEditor({
    super.key,
    required this.points,
    required this.onChanged,
    required this.resolver,
    required this.mapCenterLatitude,
    required this.mapCenterLongitude,
  });

  final List<EventRoutePoint> points;
  final ValueChanged<List<EventRoutePoint>> onChanged;
  final AddressResolver resolver;
  final double mapCenterLatitude;
  final double mapCenterLongitude;

  @override
  State<EventRouteEditor> createState() => _EventRouteEditorState();
}

class _EventRouteEditorState extends State<EventRouteEditor> {
  final _controller = TextEditingController();
  var _resolving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _full => widget.points.length >= maxEventRoutePoints;

  Future<void> _addFromText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _resolving) return;
    if (_full) {
      setState(() => _error = 'Не больше $maxEventRoutePoints точек');
      return;
    }

    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final point = await widget.resolver.resolve(text);
      if (!mounted) return;
      if (point == null) {
        setState(() {
          _resolving = false;
          _error = 'Адрес не найден. Уточните его или поставьте точку на карте';
        });
        return;
      }
      widget.onChanged([...widget.points, point]);
      _controller.clear();
      setState(() => _resolving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'Не удалось найти адрес — проверьте соединение';
      });
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<List<EventRoutePoint>>(
      MaterialPageRoute(
        builder: (_) => EventRoutePickerScreen(
          initial: widget.points,
          centerLatitude: widget.mapCenterLatitude,
          centerLongitude: widget.mapCenterLongitude,
        ),
      ),
    );
    if (result != null) widget.onChanged(result);
  }

  void _remove(int index) {
    widget.onChanged([...widget.points]..removeAt(index));
  }

  void _reorder(int from, int to) {
    final next = [...widget.points];
    next.insert(to, next.removeAt(from));
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.resolver.suggestions(_controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Маршрут'),
        const SizedBox(height: 10),
        Text(
          'Необязательно. Добавьте точки по порядку: по адресам или прямо на карте.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (widget.points.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: widget.points.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final point = widget.points[index];
              return _PointTile(
                key: ValueKey('route-point-$index-${point.latitude}-${point.longitude}'),
                index: index,
                point: point,
                onRemove: () => _remove(index),
              );
            },
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: widget.points.isEmpty
                      ? 'Адрес или место: «Морской порт»'
                      : 'Следующая точка',
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _addFromText(),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Добавить точку маршрута',
              child: IconButton.filled(
                onPressed: _resolving || _full ? null : _addFromText,
                tooltip: 'Добавить точку',
                icon: _resolving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.add),
              ),
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final place in suggestions)
                ActionChip(
                  label: Text(place.title),
                  onPressed: () {
                    widget.onChanged([
                      ...widget.points,
                      EventRoutePoint(
                        latitude: place.latitude,
                        longitude: place.longitude,
                        title: place.title,
                      ),
                    ]);
                    _controller.clear();
                    setState(() => _error = null);
                  },
                  backgroundColor: AppColors.card,
                  side: BorderSide(color: AppColors.hair),
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        // Карты на вебе нет — там остаётся только ввод адресов.
        if (!kIsWeb) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickOnMap,
            icon: const Icon(Icons.map_outlined),
            label: Text(
              widget.points.isEmpty
                  ? 'Поставить точки на карте'
                  : 'Изменить на карте',
            ),
          ),
        ],
      ],
    );
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({
    super.key,
    required this.index,
    required this.point,
    required this.onRemove,
  });

  final int index;
  final EventRoutePoint point;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final label = point.title ??
        'Точка на карте · ${point.latitude.toStringAsFixed(4)}, '
            '${point.longitude.toStringAsFixed(4)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text(
              '${index + 1}',
              style: AppTypography.serif(13, color: AppColors.onPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Убрать точку ${index + 1}',
            icon: Icon(Icons.close, size: 18, color: AppColors.textDim),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Icon(Icons.drag_handle, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
