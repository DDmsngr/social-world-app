import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/markdown_view.dart';

/// Поле текста поста с необязательным Markdown: панель вставки синтаксиса и
/// предпросмотр. Для статьи Markdown включён всегда, для момента — по
/// переключателю.
class PostBodyEditor extends StatefulWidget {
  const PostBodyEditor({
    super.key,
    required this.controller,
    required this.markdown,
    required this.onMarkdownChanged,
    required this.maxLength,
    this.alwaysMarkdown = false,
    this.hint = 'Напишите, что увидели или куда зовёте',
    this.minLines = 4,
    this.maxLines = 8,
    this.onInsertImage,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool markdown;
  final ValueChanged<bool> onMarkdownChanged;
  final int maxLength;

  /// Статья: переключателя нет, Markdown включён.
  final bool alwaysMarkdown;
  final String hint;
  final int minLines;
  final int maxLines;

  /// Загружает фото и возвращает ссылку для вставки в текст. Не задан — кнопки
  /// «фото» нет.
  final Future<String?> Function()? onInsertImage;
  final VoidCallback? onChanged;

  @override
  State<PostBodyEditor> createState() => _PostBodyEditorState();
}

class _PostBodyEditorState extends State<PostBodyEditor> {
  var _preview = false;
  var _insertingImage = false;

  bool get _markdownOn => widget.alwaysMarkdown || widget.markdown;

  TextEditingController get _c => widget.controller;

  void _notify() => widget.onChanged?.call();

  /// Оборачивает выделенное (или подставляет заглушку) парой знаков.
  void _wrap(String left, String right, {String placeholder = 'текст'}) {
    final value = _c.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final selected = value.text.substring(start, end);
    final inner = selected.isEmpty ? placeholder : selected;

    final text = value.text.replaceRange(start, end, '$left$inner$right');
    _c.value = TextEditingValue(
      text: text,
      // Выделяем вставленное слово: его сразу можно заменить набором.
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + inner.length,
      ),
    );
    _notify();
  }

  /// Ставит префикс в начало строки, где стоит курсор («## », «- », «> »).
  void _linePrefix(String prefix) {
    final value = _c.value;
    final sel = value.selection;
    final pos = sel.isValid ? sel.start : value.text.length;
    final lineStart = value.text.lastIndexOf('\n', pos == 0 ? 0 : pos - 1) + 1;
    final text = value.text.replaceRange(lineStart, lineStart, prefix);
    _c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    _notify();
  }

  Future<void> _image() async {
    final pick = widget.onInsertImage;
    if (pick == null || _insertingImage) return;
    setState(() => _insertingImage = true);
    try {
      final url = await pick();
      if (url != null && mounted) {
        _wrap('![', ']($url)', placeholder: 'фото');
      }
    } finally {
      if (mounted) setState(() => _insertingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.alwaysMarkdown)
          SwitchListTile(
            value: widget.markdown,
            onChanged: (value) {
              widget.onMarkdownChanged(value);
              if (!value) setState(() => _preview = false);
            },
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.onPrimary,
            activeTrackColor: AppColors.primary,
            title: const Text('Форматирование Markdown'),
            subtitle: Text(
              'Заголовки, списки, ссылки, **жирный**',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
        if (_markdownOn) ...[
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
                      _Tool(
                        Icons.format_list_bulleted,
                        'Список',
                        () => _linePrefix('- '),
                      ),
                      _Tool(Icons.format_quote, 'Цитата', () => _linePrefix('> ')),
                      _Tool(Icons.code, 'Код', () => _wrap('`', '`', placeholder: 'код')),
                      _Tool(
                        Icons.link,
                        'Ссылка',
                        () => _wrap('[', '](https://)', placeholder: 'текст ссылки'),
                      ),
                      if (widget.onInsertImage != null)
                        _insertingImage
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _Tool(Icons.image_outlined, 'Фото в текст', _image),
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
          const SizedBox(height: 4),
        ],
        if (_markdownOn && _preview)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 140),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(color: AppColors.hair),
            ),
            child: _c.text.trim().isEmpty
                ? Text(
                    'Пока пусто',
                    style: TextStyle(color: AppColors.textFaint),
                  )
                : MarkdownView(data: _c.text),
          )
        else
          TextField(
            controller: _c,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: widget.hint,
              alignLabelWithHint: true,
            ),
            onChanged: (_) => _notify(),
          ),
      ],
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
