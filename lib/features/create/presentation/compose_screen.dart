import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../chat/presentation/widgets/schedule_picker.dart';
import '../../discover/domain/entities/place.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../events/data/address_resolver.dart';
import '../../events/domain/entities/event_route.dart';
import '../../events/presentation/providers/events_providers.dart';
import '../../events/presentation/widgets/event_route_editor.dart';
import '../../feed/domain/entities/post.dart';
import '../../feed/domain/repositories/feed_repository.dart';
import '../../feed/presentation/providers/feed_providers.dart';
import '../../feed/presentation/providers/publish_settings_provider.dart';
import '../../feed/presentation/widgets/publish_settings_panel.dart';
import 'widgets/article_editor.dart';
import 'widgets/article_media.dart';
import 'widgets/composer_parts.dart';
import 'widgets/post_body_editor.dart';

/// Что пишем на этом экране. Квест, «Мне надо» и маршрут устроены иначе и
/// открываются своими экранами прямо с выбора на вкладке «+».
enum ComposeKind {
  moment('moment', 'Новый момент'),
  article('article', 'Новая статья'),
  event('event', 'Новое событие');

  const ComposeKind(this.segment, this.title);

  final String segment;
  final String title;

  bool get isPost => this != event;

  static ComposeKind fromSegment(String? value) =>
      values.where((kind) => kind.segment == value).firstOrNull ?? moment;
}

String _formatStartsAt(DateTime time) {
  final dd = time.day.toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  final hh = time.hour.toString().padLeft(2, '0');
  final min = time.minute.toString().padLeft(2, '0');
  return '$dd.$mm, $hh:$min';
}

/// Один экран на один вид публикации. Главное сверху (текст, фото, название),
/// всё второстепенное — свёрнутыми строками «Место», «Кому видно»; кнопка
/// «Опубликовать» всегда на виду в шапке, а не в конце длинной формы.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, required this.kind});

  final ComposeKind kind;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  ComposeKind get _kind => widget.kind;

  final _bodyController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final _geocoder = NominatimGeocoder();
  final _attachments = <XFile>[];
  final _article = ArticleController();
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
  void initState() {
    super.initState();
    _article.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _article.dispose();
    _bodyController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Есть что терять при выходе: тогда спрашиваем, а не стираем молча.
  bool get _dirty =>
      _bodyController.text.trim().isNotEmpty ||
      _titleController.text.trim().isNotEmpty ||
      _descriptionController.text.trim().isNotEmpty ||
      _article.markdown.trim().isNotEmpty ||
      _attachments.isNotEmpty ||
      _startsAt != null;

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      if (_kind.isPost) {
        await _publishPost();
      } else {
        await _publishEvent();
      }
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
    final isArticle = _kind == ComposeKind.article;
    final settings = ref.read(publishSettingsProvider).current;

    final post = await ref.read(feedRepositoryProvider).createPost(
      body: isArticle ? _article.markdown : _bodyController.text,
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

  FeedRepository get _feedRepo => ref.read(feedRepositoryProvider);

  void _uploadFailed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(error, fallback: 'Не загрузилось'))),
    );
  }

  /// Фото и видео в тексте статьи нужны в хранилище ещё до публикации, чтобы
  /// получить ссылку для Markdown.
  Future<List<String>> _pickArticleImages(int limit, UploadProgress onProgress) =>
      pickArticleImages(
        picker: _picker,
        repository: _feedRepo,
        limit: limit,
        onError: _uploadFailed,
        onProgress: onProgress,
      );

  Future<String?> _pickArticleVideo(UploadProgress onProgress) => pickArticleVideo(
    picker: _picker,
    repository: _feedRepo,
    onError: _uploadFailed,
    onProgress: onProgress,
  );

  Future<void> _pickStartsAt() async {
    final at = await showSchedulePicker(
      context,
      title: 'Когда событие',
      action: 'Назначить',
    );
    if (at != null && mounted) setState(() => _startsAt = at);
  }

  bool get _canPublish {
    if (_busy) return false;
    return switch (_kind) {
      ComposeKind.moment =>
        _bodyController.text.trim().length >= 3 || _attachments.isNotEmpty,
      ComposeKind.article =>
        _titleController.text.trim().length >= 3 &&
            _article.markdown.trim().length >= 20 &&
            _article.markdown.length <= ArticleController.maxLength,
      ComposeKind.event =>
        _titleController.text.trim().length >= 3 && _startsAt != null,
    };
  }

  /// Что не хватает до публикации — одной строкой, чтобы неактивная кнопка не
  /// была загадкой.
  String? get _missing {
    if (_canPublish || _busy) return null;
    return switch (_kind) {
      ComposeKind.moment => 'Напишите хотя бы пару слов или добавьте фото',
      ComposeKind.article => _titleController.text.trim().length < 3
          ? 'Нужен заголовок'
          : _article.markdown.length > ArticleController.maxLength
          ? 'Текст слишком длинный'
          : 'Нужен текст статьи',
      ComposeKind.event => _titleController.text.trim().length < 3
          ? 'Нужно название'
          : 'Выберите дату и время',
    };
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Выйти без публикации?'),
        content: const Text('Написанное пропадёт.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _pickPlace(List<Place> places) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.ink2,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Место', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Необязательно. Указывается название места, а не ваши координаты. '
                'Нажмите на выбранное ещё раз, чтобы убрать.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              PlacePicker(
                places: places,
                selectedId: _selectedPlace?.id,
                onChanged: (place) {
                  setState(() => _selectedPlace = place);
                  Navigator.pop(sheet);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Свёрнутая строка параметра: что выбрано сейчас и куда нажать.
  Widget _optionRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryTint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  Text(value, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                tooltip: 'Убрать',
                icon: Icon(Icons.close, size: 18, color: AppColors.textFaint),
              )
            else
              Icon(Icons.chevron_right, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(discoverDataProvider).value?.places ?? const <Place>[];
    final center = ref.watch(discoverCenterProvider).value;
    final theme = Theme.of(context);
    final missing = _missing;

    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_kind.title),
          leading: IconButton(
            onPressed: () async {
              if (!_dirty || await _confirmDiscard()) {
                if (context.mounted) {
                  context.canPop() ? context.pop() : context.go(Routes.create);
                }
              }
            },
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _canPublish ? _publish : null,
                style: AppButtons.compact,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Опубликовать'),
              ),
            ),
          ],
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: AppSpacing.page(context, top: AppSpacing.gutter),
          children: [
            if (_kind == ComposeKind.moment) ...[
              PostBodyEditor(
                controller: _bodyController,
                markdown: _markdown,
                onMarkdownChanged: (value) => setState(() => _markdown = value),
                maxLength: 500,
                onChanged: () => setState(() {}),
              ),
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
            if (_kind == ComposeKind.article) ...[
              TextField(
                controller: _titleController,
                maxLength: 160,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(hintText: 'Заголовок'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              ArticleEditor(
                controller: _article,
                onPickImages: _pickArticleImages,
                onPickVideo: _pickArticleVideo,
              ),
            ],
            if (_kind == ComposeKind.event) ...[
              TextField(
                controller: _titleController,
                maxLength: 80,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(hintText: 'Название события'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _optionRow(
                icon: Icons.event_outlined,
                title: 'Когда',
                value: _startsAt == null ? 'Выбрать дату и время' : _formatStartsAt(_startsAt!),
                onTap: _pickStartsAt,
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
            ],
            const SizedBox(height: 14),
            _optionRow(
              icon: Icons.place_outlined,
              title: 'Место',
              value: _selectedPlace?.title ?? 'Не указано',
              onTap: () => _pickPlace(places),
              onClear: _selectedPlace == null ? null : () => setState(() => _selectedPlace = null),
            ),
            if (_kind == ComposeKind.event) ...[
              const SizedBox(height: 10),
              Theme(
                // Без разделителей ExpansionTile: карточка и так обведена.
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    leading: Icon(Icons.route, color: AppColors.primaryTint),
                    title: const Text('Маршрут события'),
                    subtitle: Text(
                      _routePoints.isEmpty
                          ? 'Необязательно'
                          : 'Точек: ${_routePoints.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      EventRouteEditor(
                        points: _routePoints,
                        onChanged: (points) => setState(() => _routePoints = points),
                        resolver: AddressResolver(places: places, geocoder: _geocoder),
                        mapCenterLatitude: center?.latitude ?? discoverCenterLatitude,
                        mapCenterLongitude: center?.longitude ?? discoverCenterLongitude,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_kind.isPost) ...[
              const SizedBox(height: 10),
              const PublishSettingsPanel(),
            ],
            if (missing != null) ...[
              const SizedBox(height: 16),
              Text(
                missing,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
