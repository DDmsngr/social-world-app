import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/permissions/content_permissions.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../create/presentation/widgets/article_editor.dart';
import '../../create/presentation/widgets/article_media.dart';
import '../../create/presentation/widgets/composer_parts.dart';
import '../../create/presentation/widgets/post_body_editor.dart';
import '../../discover/domain/entities/place.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../domain/entities/post.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../domain/entities/publish_settings.dart';
import 'providers/feed_providers.dart';
import 'widgets/publish_settings_panel.dart';

/// Правка собственного поста: текст, Markdown, вложения, место, видимость.
/// Чужой пост экран не открывает — это проверяется и здесь, и в репозитории,
/// и на сервере.
class PostEditScreen extends ConsumerStatefulWidget {
  const PostEditScreen({super.key, required this.postId, this.post});

  final String postId;
  final Post? post;

  @override
  ConsumerState<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends ConsumerState<PostEditScreen> {
  Post? _post;
  var _loading = true;

  final _title = TextEditingController();
  final _body = TextEditingController();
  final _article = ArticleController();
  final _picker = ImagePicker();

  var _markdown = false;
  late PublishSettings _settings;
  late List<String> _keepMedia;
  final _newMedia = <XFile>[];
  String? _placeId;
  String? _placeTitle;
  double? _placeLat;
  double? _placeLng;
  var _busy = false;

  static const _maxAttachments = 4;

  @override
  void initState() {
    super.initState();
    _article.addListener(() {
      if (mounted) setState(() {});
    });
    _resolve();
  }

  @override
  void dispose() {
    _article.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    Post? post = widget.post;
    if (post == null) {
      for (final item in ref.read(feedProvider).value ?? const <Post>[]) {
        if (item.id == widget.postId) post = item;
      }
    }
    post ??= await ref.read(feedRepositoryProvider).loadPost(widget.postId);
    if (!mounted) return;

    if (post != null) {
      _title.text = post.title ?? '';
      _body.text = post.body ?? '';
      if (post.isArticle) _article.load(post.body ?? '');
      _markdown = post.bodyFormat == BodyFormat.markdown;
      _settings = PublishSettings(
        visibility: post.visibility,
        showGeo: post.showGeo,
      );
      _keepMedia = [...post.mediaUrls];
      _placeId = post.placeId;
      _placeTitle = post.placeTitle;
      _placeLat = post.placeLatitude;
      _placeLng = post.placeLongitude;
    }
    setState(() {
      _post = post;
      _loading = false;
    });
    if (post != null) _initial = _snapshot();
  }

  /// Слепок формы на момент открытия: по нему видно, что человек что-то
  /// изменил, и системная «назад» не выбрасывает правки молча.
  String _initial = '';

  String _snapshot() => [
    _title.text,
    _isArticle ? _article.markdown : _body.text,
    _keepMedia.join(','),
    _newMedia.length,
    _settings.toJson(),
    _placeId,
    _markdown,
  ].join('|');

  bool get _dirty => !_loading && _post != null && _snapshot() != _initial;

  /// Спрашивает, уходить ли без сохранения. Возвращает true — можно уходить.
  Future<bool> _confirmLeave() async {
    if (!_dirty || _busy) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти без сохранения?'),
        content: const Text('Изменения в публикации пропадут.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  void _leave() => context.canPop() ? context.pop() : context.go(Routes.feed);

  bool get _isArticle => _post?.isArticle ?? false;
  int get _freeSlots => _maxAttachments - _keepMedia.length - _newMedia.length;

  bool get _canSave {
    if (_busy) return false;
    final text = _body.text.trim();
    if (_isArticle) {
      final article = _article.markdown;
      return _title.text.trim().isNotEmpty &&
          article.trim().length >= 20 &&
          article.length <= ArticleController.maxLength;
    }
    return text.length >= 3 || _keepMedia.isNotEmpty || _newMedia.isNotEmpty;
  }

  Future<void> _addPhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() => _newMedia.addAll(picked.take(_freeSlots)));
  }

  void _uploadFailed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(error, fallback: 'Не загрузилось'))),
    );
  }

  Future<List<String>> _pickArticleImages(int limit, UploadProgress onProgress) =>
      pickArticleImages(
        picker: _picker,
        repository: ref.read(feedRepositoryProvider),
        limit: limit,
        onError: _uploadFailed,
        onProgress: onProgress,
      );

  Future<String?> _pickArticleVideo(UploadProgress onProgress) => pickArticleVideo(
    picker: _picker,
    repository: ref.read(feedRepositoryProvider),
    onError: _uploadFailed,
    onProgress: onProgress,
  );

  Future<void> _save() async {
    final post = _post;
    if (post == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(feedRepositoryProvider).updatePost(
        post,
        body: _isArticle ? _article.markdown : _body.text,
        title: _isArticle ? _title.text : null,
        bodyFormat: _isArticle
            ? BodyFormat.markdown
            : (_markdown ? BodyFormat.markdown : BodyFormat.plain),
        settings: _settings,
        keepMediaUrls: _keepMedia,
        newMediaPaths: [for (final file in _newMedia) file.path],
        placeId: _placeId,
        placeTitle: _placeTitle,
        placeLatitude: _placeLat,
        placeLongitude: _placeLng,
      );
      ref.read(feedProvider.notifier).replacePost(updated);
      ref.invalidate(userPostsProvider(post.authorId));

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.canPop() ? context.pop() : context.go(Routes.feed);
      messenger.showSnackBar(const SnackBar(content: Text('Изменения сохранены')));
    } catch (error) {
      AppLog.add('Правка поста не сохранилась: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось сохранить'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider)?.id;
    final post = _post;
    final places = ref.watch(discoverDataProvider).value?.places ?? const <Place>[];

    Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (post == null) {
      body = const StateMessage(
        title: 'Публикация не найдена',
        text: 'Возможно, её уже удалили.',
        icon: Icons.search_off,
      );
    } else if (!ContentPermissions(viewerId: me, ownerId: post.authorId).isOwner) {
      body = const StateMessage(
        title: 'Это чужая публикация',
        text: 'Редактировать можно только свои материалы.',
        icon: Icons.lock_outline,
      );
    } else {
      body = ListView(
        padding: AppSpacing.page(context),
        children: [
          if (_isArticle) ...[
            TextField(
              controller: _title,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Заголовок статьи'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          if (_isArticle)
            ArticleEditor(
              controller: _article,
              onPickImages: _pickArticleImages,
              onPickVideo: _pickArticleVideo,
            )
          else
            PostBodyEditor(
              controller: _body,
              markdown: _markdown,
              onMarkdownChanged: (value) => setState(() => _markdown = value),
              maxLength: 500,
              hint: 'Текст',
              onChanged: () => setState(() {}),
            ),
          const SizedBox(height: 12),
          if (!post.isRoute) ...[
            if (!_isArticle)
              Row(
                children: [
                  AttachButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Добавить фото',
                    onTap: _freeSlots <= 0 ? null : _addPhotos,
                  ),
                ],
              ),
            if (_keepMedia.isNotEmpty || _newMedia.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final url in _keepMedia)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ExistingMediaThumb(
                          url: url,
                          onRemove: () => setState(() => _keepMedia.remove(url)),
                        ),
                      ),
                    for (final file in _newMedia)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AttachmentThumb(
                          file: file,
                          onRemove: () => setState(() => _newMedia.remove(file)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 22),
          const SectionLabel('Место'),
          const SizedBox(height: 12),
          PlacePicker(
            places: places,
            selectedId: _placeId,
            onChanged: (place) => setState(() {
              _placeId = place?.id;
              _placeTitle = place?.title;
              _placeLat = place?.latitude;
              _placeLng = place?.longitude;
            }),
          ),
          if (_placeId != null && !places.any((p) => p.id == _placeId)) ...[
            const SizedBox(height: 8),
            Text(
              'Сейчас: ${_placeTitle ?? 'место'}. Выберите другое или оставьте.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 22),
          const SectionLabel('Настройки публикации'),
          const SizedBox(height: 12),
          PublishSettingsFields(
            settings: _settings,
            onChanged: (next) => setState(() => _settings = next),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      );
    }

    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isArticle ? 'Правка статьи' : 'Правка публикации'),
          leading: IconButton(
            onPressed: () async {
              if (await _confirmLeave() && mounted) _leave();
            },
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: body,
      ),
    );
  }
}
