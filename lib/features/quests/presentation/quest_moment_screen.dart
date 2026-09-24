import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../create/presentation/widgets/composer_parts.dart';
import '../../feed/domain/entities/post.dart';
import '../../feed/presentation/providers/feed_providers.dart';
import '../../feed/presentation/providers/publish_settings_provider.dart';
import '../../feed/presentation/widgets/publish_settings_panel.dart';
import '../data/local_quests_repository.dart';
import '../domain/entities/quest.dart';
import 'providers/quests_providers.dart';

/// Quest Moment (п. 37–39): обычный момент со связью с квестом. Одна
/// фотография на человека на квест (п. 38) — поэтому здесь одно фото, а не
/// галерея. Публикуется в ленту по обычным настройкам приватности (п. 45).
class QuestMomentScreen extends ConsumerStatefulWidget {
  const QuestMomentScreen({super.key, required this.questId, this.quest});

  final String questId;
  final Quest? quest;

  @override
  ConsumerState<QuestMomentScreen> createState() => _QuestMomentScreenState();
}

class _QuestMomentScreenState extends ConsumerState<QuestMomentScreen> {
  final _body = TextEditingController();
  final _picker = ImagePicker();
  XFile? _photo;
  var _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file != null) setState(() => _photo = file);
  }

  bool get _canPublish => !_busy && (_photo != null || _body.text.trim().length >= 3);

  Future<void> _publish(Quest? quest) async {
    setState(() => _busy = true);
    try {
      final post = await ref.read(feedRepositoryProvider).createPost(
        body: _body.text,
        postType: PostType.moment,
        settings: ref.read(publishSettingsProvider).current,
        mediaPaths: [?_photo?.path],
        placeId: quest?.placeId,
        placeTitle: quest?.placeTitle,
        placeLatitude: quest?.placeId == null ? null : quest?.latitude,
        placeLongitude: quest?.placeId == null ? null : quest?.longitude,
        questId: widget.questId,
      );
      ref.read(feedProvider.notifier).prepend(post);
      ref.invalidate(myPostsProvider);

      // Без сервера история квеста живёт в заглушке — дописываем туда же.
      final repo = ref.read(questsRepositoryProvider);
      if (repo is LocalQuestsRepository) {
        repo.addMoment(
          widget.questId,
          QuestMoment(
            postId: post.id,
            authorId: post.authorId,
            authorName: post.authorName,
            authorAvatarUrl: post.authorAvatarUrl,
            photoUrl: post.mediaUrls.firstOrNull,
            body: post.body,
            createdAt: post.createdAt,
          ),
        );
      }
      ref
        ..invalidate(questMomentsProvider(widget.questId))
        ..invalidate(questProvider(widget.questId));

      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Момент добавлен к квесту и в вашу ленту')),
      );
    } catch (error) {
      AppLog.add('Quest Moment не опубликован: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось опубликовать'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quest = ref.watch(questProvider(widget.questId)).value ?? widget.quest;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Момент квеста')),
      body: ListView(
        padding: AppSpacing.page(context),
        children: [
          if (quest != null) ...[
            Text(
              quest.title,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],
          Text('Как всё прошло?', style: AppTypography.serif(30)),
          const SizedBox(height: 8),
          Text(
            'Одна фотография на квест. Момент появится в вашей ленте и в '
            'истории квеста — по вашим обычным настройкам приватности.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_photo == null)
            Row(
              children: [
                AttachButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Снять',
                  onTap: () => _pick(ImageSource.camera),
                ),
                const SizedBox(width: 8),
                AttachButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Из галереи',
                  onTap: () => _pick(ImageSource.gallery),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: AttachmentThumb(
                file: _photo!,
                onRemove: () => setState(() => _photo = null),
              ),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _body,
            maxLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Пара слов (необязательно)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const PublishSettingsPanel(),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _canPublish ? () => _publish(quest) : null,
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
