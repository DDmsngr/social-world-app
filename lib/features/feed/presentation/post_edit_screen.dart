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
    _resolve();
  }

  @override
  void dispose() {
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
  }

  bool get _isArticle => _post?.isArticle ?? false;
  int get _freeSlots => _maxAttachments - _keepMedia.length - _newMedia.length;

  bool get _canSave {
    if (_busy) return false;
    final text = _body.text.trim();
    if (_isArticle) return _title.text.trim().isNotEmpty && text.length >= 20;
    return text.length >= 3 || _keepMedia.isNotEmpty || _newMedia.isNotEmpty;
  }

  Future<void> _addPhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() => _newMedia.addAll(picked.take(_freeSlots)));
  }

  Future<String?> _insertImage() async {
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
          SnackBar(content: Text(friendlyError(error, fallback: 'Фото не загрузилось'))),
        );
      }
      return null;
    }
  }

  Future<void> _save() async {
    final post = _post;
    if (post == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(feedRepositoryProvider).updatePost(
        post,
        body: _body.text,
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
          PostBodyEditor(
            controller: _body,
            markdown: _markdown,
            alwaysMarkdown: _isArticle,
            onMarkdownChanged: (value) => setState(() => _markdown = value),
            maxLength: _isArticle ? 20000 : 500,
            minLines: _isArticle ? 10 : 4,
            maxLines: _isArticle ? 24 : 8,
            hint: _isArticle ? 'Текст статьи' : 'Текст',
            onInsertImage: _isArticle ? _insertImage : null,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (!post.isRoute) ...[
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isArticle ? 'Правка статьи' : 'Правка публикации'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.feed),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: body,
    );
  }
}
