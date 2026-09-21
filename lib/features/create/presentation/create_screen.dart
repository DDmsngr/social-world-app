import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../discover/domain/entities/place.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../events/data/address_resolver.dart';
import '../../events/domain/entities/event_route.dart';
import '../../events/presentation/providers/events_providers.dart';
import '../../events/presentation/widgets/event_route_editor.dart';
import '../../feed/domain/entities/post.dart';
import '../../feed/presentation/providers/feed_providers.dart';
import '../../feed/presentation/providers/publish_settings_provider.dart';
import '../../feed/presentation/widgets/publish_settings_panel.dart';
import 'widgets/composer_parts.dart';
import 'widgets/post_body_editor.dart';

enum _CreateKind {
  moment('Момент'),
  article('Статья'),
  event('Событие'),
  route('Маршрут');

  const _CreateKind(this.label);

  final String label;

  bool get isPost => this == moment || this == article;
}

String _formatStartsAt(DateTime time) {
  final dd = time.day.toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  final hh = time.hour.toString().padLeft(2, '0');
  final min = time.minute.toString().padLeft(2, '0');
  return '$dd.$mm, $hh:$min';
}

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  var _kind = _CreateKind.moment;

  final _bodyController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final _geocoder = NominatimGeocoder();
  final _attachments = <XFile>[];
  var _markdown = false;

  // Место храним целиком, а не только название: у places title не уникален
  // (тем более при краудсорсинге), резолвить id обратно по строке нельзя.
  Place? _selectedPlace;
  DateTime? _startsAt;
  var _routePoints = <EventRoutePoint>[];
  bool _busy = false;

  /// Больше четырёх карточка в ленте всё равно не покажет внятно, а вес
  /// публикации растёт линейно.
  static const _maxAttachments = 4;

  @override
  void dispose() {
    _bodyController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _bodyController.clear();
    _titleController.clear();
    _descriptionController.clear();
    _attachments.clear();
    _routePoints = [];
    _selectedPlace = null;
    _startsAt = null;
    _markdown = false;
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      if (_kind.isPost) {
        await _publishPost();
      } else {
        await _publishEvent();
      }
      if (!mounted) return;
      setState(() {
        _resetForm();
        _busy = false;
      });
    } catch (error) {
      // Загрузка вложений — самое частое место реального падения здесь, а
      // snackbar не говорит, что именно отказало (сеть, RLS, лимит размера
      // на прокси). Без adb это единственный способ увидеть причину.
      AppLog.add('Публикация не удалась: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: 'Не удалось опубликовать')),
        ),
      );
    }
  }

  Future<void> _publishPost() async {
    final isArticle = _kind == _CreateKind.article;
    final settings = ref.read(publishSettingsProvider).current;

    final post = await ref.read(feedRepositoryProvider).createPost(
      body: _bodyController.text,
      postType: isArticle ? PostType.article : PostType.moment,
      title: isArticle ? _titleController.text : null,
      bodyFormat: isArticle || _markdown ? BodyFormat.markdown : BodyFormat.plain,
      settings: settings,
      mediaPaths: [for (final file in _attachments) file.path],
      placeId: _selectedPlace?.id,
      placeTitle: _selectedPlace?.title,
      placeLatitude: _selectedPlace?.latitude,
      placeLongitude: _selectedPlace?.longitude,
    );

    // Выбранное в этой публикации становится настройкой по умолчанию для
    // следующей. Сбой записи на диск не должен портить уже сделанный пост.
    try {
      await ref.read(publishSettingsProvider.notifier).rememberAsDefault();
    } catch (error) {
      AppLog.add('Настройки публикации не запомнились: $error');
    }

    ref.read(feedProvider.notifier).prepend(post);
    ref.invalidate(myPostsProvider);
    if (mounted) context.go(Routes.feed);
  }

  Future<void> _publishEvent() async {
    final event = await ref.read(eventsRepositoryProvider).createEvent(
      title: _titleController.text,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text,
      startsAt: _startsAt!,
      placeId: _selectedPlace?.id,
      placeTitle: _selectedPlace?.title,
      routePoints: _routePoints,
    );

    // Координаты места сервер отдаёт только в city_events — подставляем
    // их из выбранного места, чтобы метка встала на карту сразу.
    final placed = event.copyWith(
      latitude: _selectedPlace?.latitude,
      longitude: _selectedPlace?.longitude,
    );
    ref.read(eventsProvider.notifier).append(placed);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    context.go(Routes.home);
    messenger.showSnackBar(
      SnackBar(
        content: Text(placed.hasLocation ? 'Событие на карте' : 'Событие создано'),
        action: SnackBarAction(
          label: 'Открыть',
          onPressed: () =>
              router.push('${Routes.eventDetail}/${placed.id}', extra: placed),
        ),
      ),
    );
  }

  int get _freeSlots => _maxAttachments - _attachments.length;

  Future<void> _addPhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() => _attachments.addAll(picked.take(_freeSlots)));
  }

  Future<void> _shootPhoto() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (shot == null) return;
    setState(() => _attachments.add(shot));
  }

  Future<void> _addVideo() async {
    // Минута — осознанный потолок: длинное видео на мобильном интернете не
    // загрузится, а пост с вечным индикатором хуже, чем пост без видео.
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 1),
    );
    if (video == null) return;
    setState(() => _attachments.add(video));
  }

  /// Фото, вставляемое прямо в текст статьи: в отличие от вложений оно нужно
  /// в хранилище ещё до публикации, чтобы получить ссылку.
  Future<String?> _insertInlineImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return null;
    try {
      return await ref.read(feedRepositoryProvider).uploadInlineImage(file.path);
    } catch (error) {
      AppLog.add('Фото в текст не загрузилось: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(error, fallback: 'Фото не загрузилось')),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _pickStartsAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _startsAt == null
          ? const TimeOfDay(hour: 19, minute: 0)
          : TimeOfDay.fromDateTime(_startsAt!),
    );
    if (time == null) return;

    setState(() {
      _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  bool get _canPublish {
    if (_busy) return false;
    return switch (_kind) {
      _CreateKind.moment =>
        _bodyController.text.trim().length >= 3 || _attachments.isNotEmpty,
      _CreateKind.article =>
        _titleController.text.trim().length >= 3 &&
            _bodyController.text.trim().length >= 20,
      _CreateKind.event =>
        _titleController.text.trim().length >= 3 && _startsAt != null,
      _CreateKind.route => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(discoverDataProvider).value?.places ?? const <Place>[];
    final center = ref.watch(discoverCenterProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Создать')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          const SectionLabel('Что публикуем'),
          const SizedBox(height: 14),
          SegmentedButton<_CreateKind>(
            showSelectedIcon: false,
            segments: [
              for (final kind in _CreateKind.values)
                ButtonSegment(
                  value: kind,
                  label: Text(kind.label, style: const TextStyle(fontSize: 13)),
                ),
            ],
            selected: {_kind},
            onSelectionChanged: (selected) =>
                setState(() => _kind = selected.first),
          ),
          const SizedBox(height: 18),
          // Маршрут не пишется формой: его записывает отдельный экран, пока
          // человек идёт по городу.
          if (_kind == _CreateKind.route) ...[
            Text('Пройдите город\nи покажите путь', style: AppTypography.serif(32)),
            const SizedBox(height: 14),
            Text(
              'Приложение запишет ваш путь, пока открыто на экране. По дороге '
              'можно снимать фото — они встанут метками прямо на маршруте. '
              'Опубликуется только то, что вы сами отправите в ленту.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => context.push(Routes.routeRecorder),
              icon: const Icon(Icons.timeline),
              label: const Text('Начать запись'),
            ),
          ],
          if (_kind == _CreateKind.moment) ...[
            Text('Что происходит\nв городе?', style: AppTypography.serif(32)),
            const SizedBox(height: 18),
            PostBodyEditor(
              controller: _bodyController,
              markdown: _markdown,
              onMarkdownChanged: (value) => setState(() => _markdown = value),
              maxLength: 500,
              onChanged: () => setState(() {}),
            ),
          ],
          if (_kind == _CreateKind.article) ...[
            Text('Расскажите\nподробно', style: AppTypography.serif(32)),
            const SizedBox(height: 8),
            Text(
              'Длинный текст с заголовком: маршрут выходных, обзор места, '
              'история. Поддерживается Markdown.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Заголовок'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            PostBodyEditor(
              controller: _bodyController,
              markdown: true,
              alwaysMarkdown: true,
              onMarkdownChanged: (_) {},
              maxLength: 20000,
              minLines: 10,
              maxLines: 24,
              hint: 'Текст статьи',
              onInsertImage: _insertInlineImage,
              onChanged: () => setState(() {}),
            ),
          ],
          if (_kind.isPost) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                AttachButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Фото',
                  onTap: _freeSlots == 0 ? null : _addPhotos,
                ),
                const SizedBox(width: 8),
                AttachButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Снять',
                  onTap: _freeSlots == 0 ? null : _shootPhoto,
                ),
                const SizedBox(width: 8),
                if (_kind == _CreateKind.moment)
                  AttachButton(
                    icon: Icons.videocam_outlined,
                    label: 'Видео',
                    onTap: _freeSlots == 0 ? null : _addVideo,
                  ),
              ],
            ),
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => AttachmentThumb(
                    file: _attachments[index],
                    onRemove: () => setState(() => _attachments.removeAt(index)),
                  ),
                ),
              ),
            ],
          ],
          if (_kind == _CreateKind.event) ...[
            Text('Соберите\nлюдей на событие', style: AppTypography.serif(32)),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Название события'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'О чём событие, что взять с собой',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickStartsAt,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _startsAt == null ? 'Выбрать дату и время' : _formatStartsAt(_startsAt!),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_kind != _CreateKind.route) ...[
            const SizedBox(height: 10),
            const SectionLabel('Место'),
            const SizedBox(height: 12),
            Text(
              'Необязательно. Указывается название места, а не ваши координаты.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            PlacePicker(
              places: places,
              selectedId: _selectedPlace?.id,
              onChanged: (place) => setState(() => _selectedPlace = place),
            ),
          ],
          if (_kind == _CreateKind.event) ...[
            const SizedBox(height: 22),
            EventRouteEditor(
              points: _routePoints,
              onChanged: (points) => setState(() => _routePoints = points),
              resolver: AddressResolver(places: places, geocoder: _geocoder),
              mapCenterLatitude: center?.latitude ?? discoverCenterLatitude,
              mapCenterLongitude: center?.longitude ?? discoverCenterLongitude,
            ),
          ],
          if (_kind.isPost) ...[
            const SizedBox(height: 22),
            const PublishSettingsPanel(),
          ],
          if (_kind != _CreateKind.route) ...[
            const SizedBox(height: 26),
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
        ],
      ),
    );
  }
}
