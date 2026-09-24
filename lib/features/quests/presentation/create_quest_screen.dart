import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../create/presentation/widgets/composer_parts.dart';
import '../../create/presentation/widgets/meeting_point_field.dart';
import '../../discover/domain/entities/place.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../events/data/address_resolver.dart';
import 'providers/quests_providers.dart';
import 'quest_rules_screen.dart';
import 'widgets/quest_format.dart';

/// Создание квеста (п. 21): фото, название, что будем делать, место
/// встречи, время, лимит участников, доп. информация. Категории на MVP нет.
/// Перед первым квестом — правила (п. 49); сервер проверяет согласие сам.
class CreateQuestScreen extends ConsumerStatefulWidget {
  const CreateQuestScreen({super.key});

  @override
  ConsumerState<CreateQuestScreen> createState() => _CreateQuestScreenState();
}

class _CreateQuestScreenState extends ConsumerState<CreateQuestScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _extra = TextEditingController();
  final _limit = TextEditingController();
  final _picker = ImagePicker();
  final _geocoder = NominatimGeocoder();

  XFile? _photo;
  MeetingPoint? _point;
  DateTime? _startsAt;
  DateTime? _endsAt;
  var _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _extra.dispose();
    _limit.dispose();
    super.dispose();
  }

  int? get _maxParticipants {
    final value = int.tryParse(_limit.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  bool get _canPublish =>
      !_busy &&
      _title.text.trim().length >= 3 &&
      _startsAt != null &&
      _point != null &&
      (_endsAt == null || _endsAt!.isAfter(_startsAt!));

  Future<DateTime?> _pickDateTime(DateTime? initial, {DateTime? notBefore}) async {
    final now = DateTime.now();
    final first = notBefore ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? first,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: initial == null
          ? TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)))
          : TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _publish() async {
    final repo = ref.read(questsRepositoryProvider);
    setState(() => _busy = true);
    try {
      // Правила — один раз, перед первым квестом. Отказ — квест не создаётся.
      final consent = await repo.loadRulesConsent();
      if (consent == null || !consent.isCurrent) {
        if (!mounted) return;
        final accepted = await QuestRulesScreen.open(context);
        if (!accepted) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }

      final point = _point!;
      final id = await repo.createQuest(
        title: _title.text,
        startsAt: _startsAt!,
        endsAt: _endsAt,
        description: _description.text.trim().isEmpty ? null : _description.text,
        extraInfo: _extra.text.trim().isEmpty ? null : _extra.text,
        photoPath: _photo?.path,
        placeId: point.placeId,
        placeTitle: point.title,
        latitude: point.latitude,
        longitude: point.longitude,
        maxParticipants: _maxParticipants,
      );
      ref
        ..invalidate(pulseQuestsProvider)
        ..invalidate(myQuestsProvider);
      if (!mounted) return;
      context.pushReplacement('${Routes.questDetail}/$id');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Квест опубликован и виден на Pulse')),
      );
    } catch (error) {
      AppLog.add('Квест не создался: $error');
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
      appBar: AppBar(title: const Text('Новый квест')),
      body: ListView(
        padding: AppSpacing.page(context),
        children: [
          Text('Позовите людей\nв реальный город', style: AppTypography.serif(30)),
          const SizedBox(height: 18),
          const SectionLabel('Фото'),
          const SizedBox(height: 10),
          if (_photo == null)
            AttachButton(
              icon: Icons.photo_outlined,
              label: 'Добавить фото',
              onTap: _pickPhoto,
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: AttachmentThumb(
                file: _photo!,
                onRemove: () => setState(() => _photo = null),
              ),
            ),
          const SizedBox(height: 18),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Велопрогулка по Морскому порту',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 4,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Что будем делать?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Место встречи'),
          const SizedBox(height: 10),
          MeetingPointField(
            value: _point,
            onChanged: (point) => setState(() => _point = point),
            places: places,
            resolver: AddressResolver(places: places, geocoder: _geocoder),
            mapCenterLatitude: center?.latitude ?? discoverCenterLatitude,
            mapCenterLongitude: center?.longitude ?? discoverCenterLongitude,
          ),
          const SizedBox(height: 18),
          const SectionLabel('Когда'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await _pickDateTime(_startsAt);
              if (picked != null) setState(() => _startsAt = picked);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(
              _startsAt == null ? 'Дата и время начала' : 'Начало: ${formatQuestTime(_startsAt!)}',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _startsAt == null
                      ? null
                      : () async {
                          final picked = await _pickDateTime(_endsAt, notBefore: _startsAt);
                          if (picked != null) setState(() => _endsAt = picked);
                        },
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    _endsAt == null
                        ? 'Окончание (необязательно)'
                        : 'До: ${formatQuestTime(_endsAt!)}',
                  ),
                ),
              ),
              if (_endsAt != null)
                IconButton(
                  onPressed: () => setState(() => _endsAt = null),
                  tooltip: 'Без окончания',
                  icon: Icon(Icons.close, color: AppColors.textDim),
                ),
            ],
          ),
          if (_endsAt != null && _startsAt != null && !_endsAt!.isAfter(_startsAt!))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Окончание должно быть позже начала',
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Без окончания квест идёт, пока вы его не завершите — хоть несколько '
            'дней, состав участников может меняться.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: 'Максимум участников',
              hintText: 'Пусто — без ограничений',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            _maxParticipants == null
                ? 'Без лимита люди присоединяются сразу, без заявок.'
                : 'С лимитом вы сами принимаете заявки и видите очки активности '
                      'заявителей.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _extra,
            maxLines: 3,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Дополнительная информация',
              hintText: 'Необязательно: что взять с собой, как найти',
              alignLabelWithHint: true,
            ),
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
          if (_point == null || _startsAt == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Нужны название, место встречи и время начала.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
