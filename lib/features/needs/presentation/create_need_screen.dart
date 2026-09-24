import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../create/presentation/widgets/meeting_point_field.dart';
import '../../discover/domain/entities/place.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../events/data/address_resolver.dart';
import 'providers/needs_providers.dart';

/// «Мне надо» (п. 15): что нужно, где примерно, сколько актуально.
class CreateNeedScreen extends ConsumerStatefulWidget {
  const CreateNeedScreen({super.key});

  @override
  ConsumerState<CreateNeedScreen> createState() => _CreateNeedScreenState();
}

enum _Lifetime {
  day('Сутки', Duration(days: 1)),
  threeDays('3 дня', Duration(days: 3)),
  week('Неделя', Duration(days: 7));

  const _Lifetime(this.label, this.duration);

  final String label;
  final Duration duration;
}

class _CreateNeedScreenState extends ConsumerState<CreateNeedScreen> {
  final _text = TextEditingController();
  final _geocoder = NominatimGeocoder();
  MeetingPoint? _point;
  var _lifetime = _Lifetime.threeDays;
  var _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canPublish => !_busy && _text.text.trim().length >= 3 && _point != null;

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      final point = _point!;
      final id = await ref.read(needsRepositoryProvider).createNeed(
        text: _text.text,
        placeId: point.placeId,
        placeTitle: point.title,
        latitude: point.latitude,
        longitude: point.longitude,
        expiresAt: DateTime.now().add(_lifetime.duration),
      );
      ref
        ..invalidate(pulseNeedsProvider)
        ..invalidate(myNeedsProvider);
      if (!mounted) return;
      context.pushReplacement('${Routes.needDetail}/$id');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Просьба на карте')),
      );
    } catch (error) {
      AppLog.add('Просьба не создалась: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось опубликовать'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(discoverDataProvider).value?.places ?? const <Place>[];
    final center = ref.watch(discoverCenterProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Мне надо')),
      body: ListView(
        padding: AppSpacing.page(context),
        children: [
          Text('Попросите город', style: AppTypography.serif(30)),
          const SizedBox(height: 8),
          Text(
            '«Нужно установить телевизор», «Ищу машину до Краснодара», '
            '«Ищу напарника для тенниса».',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 4,
            maxLength: 500,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Что нужно?',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          const SectionLabel('Где'),
          const SizedBox(height: 8),
          Text(
            'Другие увидят район, а не точку: место на карте размывается '
            'примерно до 300 метров. Заведение из списка показывается как есть.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          MeetingPointField(
            value: _point,
            onChanged: (point) => setState(() => _point = point),
            places: places,
            resolver: AddressResolver(places: places, geocoder: _geocoder),
            mapCenterLatitude: center?.latitude ?? discoverCenterLatitude,
            mapCenterLongitude: center?.longitude ?? discoverCenterLongitude,
            hint: 'Улица или район',
          ),
          const SizedBox(height: 18),
          const SectionLabel('Сколько актуально'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final item in _Lifetime.values)
                ChoiceChip(
                  label: Text(item.label),
                  selected: _lifetime == item,
                  onSelected: (_) => setState(() => _lifetime = item),
                  showCheckmark: false,
                  backgroundColor: AppColors.card,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _lifetime == item ? AppColors.onPrimary : AppColors.textDim,
                  ),
                  side: BorderSide(color: AppColors.hair),
                ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _canPublish ? _publish : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Опубликовать'),
          ),
        ],
      ),
    );
  }
}
