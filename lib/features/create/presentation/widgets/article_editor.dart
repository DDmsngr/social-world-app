import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/media/media_kind.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/markdown_view.dart';
import '../../domain/article_parts.dart';
import 'article_media.dart';

/// Один блок статьи: поле текста или фото/видео.
class ArticleBlock {
  ArticleBlock._text(String text)
    : controller = TextEditingController(text: text),
      focus = FocusNode(),
      url = null,
      alt = '';

  ArticleBlock._media(this.url, this.alt) : controller = null, focus = null;

  final TextEditingController? controller;
  final FocusNode? focus;
  final String? url;
  final String alt;

  bool get isMedia => url != null;
  bool get isEmptyText => !isMedia && controller!.text.trim().isEmpty;

  void dispose() {
    controller?.dispose();
    focus?.dispose();
  }
}

/// Состояние редактора статьи. Блоки всегда чередуются так, что до первого
/// медиа, после последнего и между любыми двумя стоит текстовое поле.
class ArticleController extends ChangeNotifier {
  ArticleController([String markdown = '']) {
    load(markdown);
  }

  static const maxLength = 20000;

  final blocks = <ArticleBlock>[];
  ArticleBlock? _lastText;
  var _disposed = false;

  String get markdown => serializeArticle([
    for (final b in blocks)
      if (b.isMedia) MediaPart(b.url!, b.alt) else TextPart(b.controller!.text),
  ]);

  int get mediaCount => blocks.where((b) => b.isMedia).length;

  /// Поле, куда попадут вставка и форматирование: то, где стоял курсор.
  ArticleBlock get target =>
      blocks.contains(_lastText) ? _lastText! : blocks.lastWhere((b) => !b.isMedia);

  ArticleBlock _text(String text) {
    final block = ArticleBlock._text(text);
    block.focus!.addListener(() {
      if (block.focus!.hasFocus) _lastText = block;
    });
    return block;
  }

  void load(String markdown) {
    for (final b in blocks) {
      _retire(b);
    }
    blocks.clear();
    for (final part in parseArticle(markdown)) {
      blocks.add(
        switch (part) {
          TextPart(:final text) => _text(text),
          MediaPart(:final url, :final alt) => ArticleBlock._media(url, alt),
        },
      );
    }
    _lastText = null;
    notifyListeners();
  }

  /// Текст в одном из полей изменился.
  void touch() => notifyListeners();

  /// Ставит фото или видео в место курсора, разрезая текстовое поле надвое.
  void insertMedia(String url, String alt) {
    final block = target;
    final c = block.controller!;
    final text = c.text;
    final sel = c.selection;
    final at = sel.isValid ? sel.end.clamp(0, text.length) : text.length;

    final after = _text(text.substring(at).trimLeft());
    after.controller!.selection = const TextSelection.collapsed(offset: 0);
    c.text = text.substring(0, at).trimRight();

    final i = blocks.indexOf(block);
    blocks.insertAll(i + 1, [ArticleBlock._media(url, alt), after]);
    _lastText = after;
    _normalize();
    notifyListeners();
  }

  /// Куда уйдёт медиа при сдвиге. Пустые поля и соседнее медиа перепрыгиваются,
  /// иначе два фото подряд не поменять местами.
  int? _moveTarget(int index, int delta) {
    var j = index + delta;
    if (j < 0 || j >= blocks.length) return null;
    if (blocks[j].isEmptyText) {
      final beyond = j + delta;
      if (beyond < 0 || beyond >= blocks.length) return null;
      j = beyond;
    }
    return j;
  }

  bool canMove(int index, int delta) => _moveTarget(index, delta) != null;

  void move(int index, int delta) {
    final j = _moveTarget(index, delta);
    if (j == null) return;
    final block = blocks.removeAt(index);
    blocks.insert(j, block);
    _normalize();
    notifyListeners();
  }

  void remove(int index) {
    _retire(blocks.removeAt(index));
    _normalize();
    notifyListeners();
  }

  void clear() => load('');

  void _normalize() {
    final out = <ArticleBlock>[];
    for (final b in blocks) {
      final last = out.isEmpty ? null : out.last;
      if (!b.isMedia && last != null && !last.isMedia) {
        final a = last.controller!;
        a.text = [a.text, b.controller!.text].where((t) => t.isNotEmpty).join('\n\n');
        if (_lastText == b) _lastText = last;
        _retire(b);
      } else if (b.isMedia && (last == null || last.isMedia)) {
        out
          ..add(_text(''))
          ..add(b);
      } else {
        out.add(b);
      }
    }
    if (out.isEmpty || out.last.isMedia) out.add(_text(''));
    blocks
      ..clear()
      ..addAll(out);
  }

  /// Убранное поле ещё нарисовано в текущем кадре, поэтому освобождаем его
  /// только после кадра.
  void _retire(ArticleBlock block) {
    if (_lastText == block) _lastText = null;
    if (_disposed) {
      block.dispose();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => block.dispose());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final b in blocks) {
      b.dispose();
    }
    super.dispose();
  }
}

/// Редактор статьи «как длиннопост»: текст и фото идут друг за другом, фото
/// можно добавить в место курсора, сдвинуть выше или ниже и убрать.
class ArticleEditor extends StatefulWidget {
  const ArticleEditor({
    super.key,
    required this.controller,
    required this.onPickImages,
    required this.onPickVideo,
    this.maxMedia = 10,
  });

  final ArticleController controller;

  /// Выбирает и загружает фото (не больше переданного числа), возвращает ссылки.
  final Future<List<String>> Function(int limit, UploadProgress onProgress) onPickImages;

  /// То же для одного видео.
  final Future<String?> Function(UploadProgress onProgress) onPickVideo;
  final int maxMedia;

  @override
  State<ArticleEditor> createState() => _ArticleEditorState();
}

class _ArticleEditorState extends State<ArticleEditor> {
  var _preview = false;
  var _busy = false;
  var _label = '';
  var _fraction = 0.0;

  ArticleController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(ArticleEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != _c) {
      old.controller.removeListener(_rebuild);
      _c.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  int get _free => widget.maxMedia - _c.mediaCount;

  void _progress(String label, double fraction) {
    if (!mounted) return;
    setState(() {
      _label = label;
      _fraction = fraction.clamp(0.0, 1.0);
    });
  }

  /// Любой сбой выбора или загрузки показываем: иначе кнопки просто снова
  /// загораются, и непонятно, что пошло не так.
  void _failed(Object error) {
    AppLog.add('Вставка в статью не удалась: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(error, fallback: 'Не получилось вставить'))),
    );
  }

  Future<void> _addImages() async {
    if (_busy) return;
    if (_free <= 0) return _full();
    setState(() {
      _busy = true;
      _label = 'Выбираем фото';
      _fraction = 0;
    });
    try {
      final urls = await widget.onPickImages(_free, _progress);
      for (final url in urls.take(_free)) {
        _c.insertMedia(url, 'фото');
      }
    } catch (error) {
      _failed(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addVideo() async {
    if (_busy) return;
    if (_free <= 0) return _full();
    setState(() {
      _busy = true;
      _label = 'Выбираем видео';
      _fraction = 0;
    });
    try {
      final url = await widget.onPickVideo(_progress);
      if (url != null) _c.insertMedia(url, 'видео');
    } catch (error) {
      _failed(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _full() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('В статье можно не больше ${widget.maxMedia} фото и видео')),
    );
  }

  void _wrap(String left, String right, {String placeholder = 'текст'}) {
    final c = _c.target.controller!;
    final value = c.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final selected = value.text.substring(start, end);
    final inner = selected.isEmpty ? placeholder : selected;
    c.value = TextEditingValue(
      text: value.text.replaceRange(start, end, '$left$inner$right'),
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + inner.length,
      ),
    );
    _c.touch();
  }

  void _linePrefix(String prefix) {
    final c = _c.target.controller!;
    final value = c.value;
    final sel = value.selection;
    final pos = sel.isValid ? sel.start : value.text.length;
    final lineStart = value.text.lastIndexOf('\n', pos == 0 ? 0 : pos - 1) + 1;
    c.value = TextEditingValue(
      text: value.text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    _c.touch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length = _c.markdown.length;
    final tooLong = length > ArticleController.maxLength;
    final media = _c.blocks.where((b) => b.isMedia).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Tool(Icons.format_bold, 'Жирный', () => _wrap('**', '**')),
                    _Tool(Icons.format_italic, 'Курсив', () => _wrap('_', '_')),
                    _Tool(Icons.title, 'Заголовок', () => _linePrefix('## ')),
                    _Tool(Icons.format_list_bulleted, 'Список', () => _linePrefix('- ')),
                    _Tool(Icons.format_quote, 'Цитата', () => _linePrefix('> ')),
                    _Tool(
                      Icons.link,
                      'Ссылка',
                      () => _wrap('[', '](https://)', placeholder: 'текст ссылки'),
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else ...[
                      _Tool(Icons.image_outlined, 'Фото в текст', _addImages),
                      _Tool(Icons.videocam_outlined, 'Видео в текст', _addVideo),
                    ],
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _preview = !_preview),
              child: Text(_preview ? 'Править' : 'Просмотр'),
            ),
          ],
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fraction > 0 && _fraction < 1
                      ? '$_label · ${(_fraction * 100).round()}%'
                      : _label,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: _fraction > 0 ? _fraction : null,
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 180),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: AppColors.hair),
          ),
          child: _preview
              ? (length == 0
                    ? Text('Пока пусто', style: TextStyle(color: AppColors.textFaint))
                    : MarkdownView(data: _c.markdown))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _c.blocks.length; i++)
                      if (_c.blocks[i].isMedia)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _MediaCard(
                            key: ObjectKey(_c.blocks[i]),
                            block: _c.blocks[i],
                            number: media.indexOf(_c.blocks[i]) + 1,
                            canUp: _c.canMove(i, -1),
                            canDown: _c.canMove(i, 1),
                            onUp: () => _c.move(i, -1),
                            onDown: () => _c.move(i, 1),
                            onRemove: () => _c.remove(i),
                          ),
                        )
                      else
                        _TextBlock(
                          key: ObjectKey(_c.blocks[i]),
                          block: _c.blocks[i],
                          hint: i == 0
                              ? 'Начните писать статью'
                              : 'Текст под фото',
                          onChanged: _c.touch,
                        ),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$length/${ArticleController.maxLength}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tooLong ? theme.colorScheme.error : AppColors.textFaint,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _free <= 0 ? null : _addImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: Text('Фото ${_c.mediaCount}/${widget.maxMedia}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _free <= 0 ? null : _addVideo,
                icon: const Icon(Icons.videocam_outlined, size: 20),
                label: const Text('Видео'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Фото встанет в то место текста, где вы остановились. Потом его можно '
          'сдвинуть стрелками или убрать крестиком.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textFaint),
        ),
      ],
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    super.key,
    required this.block,
    required this.hint,
    required this.onChanged,
  });

  final ArticleBlock block;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    // Высота поля ограничена видимой частью экрана: при «выделить всё» в
    // длинном тексте ручки и «Копировать» иначе уезжали за край.
    final maxHeight =
        ((MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * 0.5)
            .clamp(220.0, 600.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: TextField(
        controller: block.controller,
        focusNode: block.focus,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: hint,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    super.key,
    required this.block,
    required this.number,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final ArticleBlock block;
  final int number;
  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  Widget _preview(BuildContext context) {
    final url = block.url!;
    final remote = url.startsWith('http');
    if (remote && isVideoUrl(url)) {
      return Container(
        height: 180,
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_outline, color: Colors.white70, size: 56),
      );
    }
    if (!remote) {
      return Container(
        height: 120,
        color: AppColors.card,
        alignment: Alignment.center,
        child: Icon(Icons.image_outlined, color: AppColors.textFaint, size: 40),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: CachedNetworkImage(
        imageUrl: url,
        width: double.infinity,
        fit: BoxFit.contain,
        placeholder: (_, _) => const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, _, _) => SizedBox(
          height: 120,
          child: Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textFaint)),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String tooltip, VoidCallback? onTap) => IconButton.filled(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, size: 20),
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.black26,
      disabledForegroundColor: Colors.white38,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: AppColors.hair)),
          _preview(context),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$number',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Row(
              children: [
                _chip(Icons.arrow_upward, 'Выше', canUp ? onUp : null),
                const SizedBox(width: 4),
                _chip(Icons.arrow_downward, 'Ниже', canDown ? onDown : null),
                const SizedBox(width: 4),
                _chip(Icons.close, 'Убрать', onRemove),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool(this.icon, this.tooltip, this.onTap);

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 20, color: AppColors.textDim),
  );
}
