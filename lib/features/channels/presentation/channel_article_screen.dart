import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/friendly_error.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../create/presentation/widgets/article_editor.dart';
import '../../create/presentation/widgets/article_media.dart';
import '../../feed/presentation/providers/feed_providers.dart';

/// Пост канала в формате статьи: заголовок, текст с Markdown и фото/видео
/// посреди текста — тот же редактор, что у статей в ленте. Уходит обычным
/// постом канала с Markdown-текстом; карточка канала рисует его с картинками.
class ChannelArticleScreen extends ConsumerStatefulWidget {
  const ChannelArticleScreen({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<ChannelArticleScreen> createState() => _ChannelArticleScreenState();
}

class _ChannelArticleScreenState extends ConsumerState<ChannelArticleScreen> {
  final _title = TextEditingController();
  final _article = ArticleController();
  final _picker = ImagePicker();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _article.addListener(_rebuild);
    _title.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _article.dispose();
    super.dispose();
  }

  void _uploadFailed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(error, fallback: 'Не загрузилось'))),
    );
  }

  /// Пост канала на сервере — до 4000 знаков (chat_messages_body_check),
  /// вместе с заголовком и ссылками на фото.
  static const maxLength = 4000;

  String get _text {
    final title = _title.text.trim();
    return [if (title.isNotEmpty) '# $title', _article.markdown.trim()].join('\n\n');
  }

  bool get _canPublish => !_busy && _article.markdown.trim().length >= 20 && _text.length <= maxLength;

  Future<void> _publish() async {
    final text = _text;
    setState(() => _busy = true);
    try {
      await ref.read(chatRepositoryProvider).send(conversationId: widget.channelId, text: text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось опубликовать'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(feedRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статья в канал'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _canPublish ? _publish : null,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Опубликовать'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _title,
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: const InputDecoration(hintText: 'Заголовок (необязательно)', counterText: ''),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_text.length}/$maxLength',
              style: TextStyle(
                fontSize: 12,
                color: _text.length > maxLength ? Theme.of(context).colorScheme.error : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ArticleEditor(
            controller: _article,
            onPickImages: (limit, onProgress) => pickArticleImages(
              picker: _picker,
              repository: repo,
              limit: limit,
              onError: _uploadFailed,
              onProgress: onProgress,
            ),
            onPickVideo: (onProgress) => pickArticleVideo(
              picker: _picker,
              repository: repo,
              onError: _uploadFailed,
              onProgress: onProgress,
            ),
          ),
        ],
      ),
    );
  }
}
