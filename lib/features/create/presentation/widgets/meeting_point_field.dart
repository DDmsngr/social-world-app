import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../discover/domain/entities/place.dart';
import '../../../events/data/address_resolver.dart';
import '../../../events/domain/entities/event_route.dart';
import '../../../events/presentation/widgets/event_route_picker.dart';
import 'composer_parts.dart';

/// Выбранная точка: заведение из places или адрес/точка на карте.
class MeetingPoint {
  const MeetingPoint({
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.title,
  });

  factory MeetingPoint.fromPlace(Place place) => MeetingPoint(
    latitude: place.latitude,
    longitude: place.longitude,
    placeId: place.id,
    title: place.title,
  );

  final double latitude;
  final double longitude;
  final String? placeId;

  /// Адрес или название, как его увидят другие.
  final String? title;

  String get label =>
      title ??
      'Точка на карте · ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
}

/// Место встречи тремя способами — заведение рядом, адрес текстом или точка
/// на карте. Все три дают одну и ту же [MeetingPoint]; повторный тап по
/// выбранному заведению или крестик снимают выбор.
class MeetingPointField extends StatefulWidget {
  const MeetingPointField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.places,
    required this.resolver,
    required this.mapCenterLatitude,
    required this.mapCenterLongitude,
    this.hint = 'Адрес: «Навагинская, 12»',
  });

  final MeetingPoint? value;
  final ValueChanged<MeetingPoint?> onChanged;
  final List<Place> places;
  final AddressResolver resolver;
  final double mapCenterLatitude;
  final double mapCenterLongitude;
  final String hint;

  @override
  State<MeetingPointField> createState() => _MeetingPointFieldState();
}

class _MeetingPointFieldState extends State<MeetingPointField> {
  final _controller = TextEditingController();
  var _resolving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _resolving) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final point = await widget.resolver.resolve(text);
      if (!mounted) return;
      setState(() => _resolving = false);
      if (point == null) {
        setState(() => _error = 'Адрес не найден. Уточните его или поставьте точку на карте');
        return;
      }
      _controller.clear();
      widget.onChanged(
        MeetingPoint(
          latitude: point.latitude,
          longitude: point.longitude,
          title: point.title ?? text,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'Не удалось найти адрес — проверьте соединение';
      });
    }
  }

  Future<void> _pickOnMap() async {
    final value = widget.value;
    final result = await Navigator.of(context).push<List<EventRoutePoint>>(
      MaterialPageRoute(
        builder: (_) => EventRoutePickerScreen(
          initial: value == null
              ? const []
              : [EventRoutePoint(latitude: value.latitude, longitude: value.longitude)],
          centerLatitude: widget.mapCenterLatitude,
          centerLongitude: widget.mapCenterLongitude,
        ),
      ),
    );
    // Экран маршрута даёт поставить несколько точек — для встречи берём
    // последнюю поставленную.
    if (result == null || result.isEmpty) return;
    final point = result.last;
    widget.onChanged(
      MeetingPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        title: point.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryTint.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Icon(Icons.place, color: AppColors.primaryTint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  onPressed: () => widget.onChanged(null),
                  tooltip: 'Убрать место',
                  icon: Icon(Icons.close, size: 18, color: AppColors.textDim),
                ),
              ],
            ),
          ),
        if (widget.places.isNotEmpty) ...[
          PlacePicker(
            places: widget.places,
            selectedId: value?.placeId,
            onChanged: (place) =>
                widget.onChanged(place == null ? null : MeetingPoint.fromPlace(place)),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(hintText: widget.hint),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _resolve(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _resolving ? null : _resolve,
              tooltip: 'Найти адрес',
              icon: _resolving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.search),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        // Карты на вебе нет — там остаются заведения и адрес.
        if (!kIsWeb) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickOnMap,
            icon: const Icon(Icons.map_outlined),
            label: Text(value == null ? 'Поставить точку на карте' : 'Изменить на карте'),
          ),
        ],
      ],
    );
  }
}
