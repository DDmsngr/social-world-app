import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/text/hashtags.dart';
import '../../../../core/theme/app_colors.dart';

/// Минимум тегов у публикации: по ним человек может скрыть ненужные темы.
const minPostTags = 2;

/// Недавно использованные теги — первые в подсказках.
abstract final class TagHistory {
  static const _key = 'recent_tags';

  static Future<List<String>> load() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remember(List<String> tags) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = [...tags, ...?prefs.getStringList(_key)];
      final seen = <String>{};
      await prefs.setStringList(_key, [for (final t in all) if (seen.add(t)) t].take(30).toList());
    } catch (_) {}
  }
}

/// Отдельная строка тегов под текстом: чипы, поле ввода и подсказки. Тег
/// добавляется пробелом, запятой или «Готово»; нужно не меньше [minPostTags].
class TagRow extends StatefulWidget {
  const TagRow({
    super.key,
    required this.tags,
    required this.onChanged,
    required this.suggestions,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  /// Что предложить: недавние и популярные теги, без «#».
  final List<String> suggestions;

  @override
  State<TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<TagRow> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final tag = normalizeHashtag(raw).replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
    if (tag.length < 2 || tag.length > 50 || widget.tags.contains(tag) || widget.tags.length >= 10) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.tags, tag]);
    _controller.clear();
  }

  void _onText(String value) {
    // Пробел или запятая в конце завершают тег.
    if (value.endsWith(' ') || value.endsWith(',') || value.endsWith('\n')) _add(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final need = minPostTags - widget.tags.length;
    final typed = normalizeHashtag(_controller.text);
    final pool = [
      for (final s in widget.suggestions)
        if (!widget.tags.contains(s) && (typed.isEmpty || s.startsWith(typed))) s,
    ].take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Теги', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(width: 8),
            Text(
              need > 0 ? 'нужно ещё $need' : 'можно добавить ещё',
              style: TextStyle(fontSize: 12.5, color: need > 0 ? AppColors.primaryTint : AppColors.textDim),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in widget.tags)
              InputChip(
                label: Text('#$tag'),
                visualDensity: VisualDensity.compact,
                onDeleted: () => widget.onChanged([...widget.tags]..remove(tag)),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autocorrect: false,
                maxLength: 51,
                textInputAction: TextInputAction.done,
                onChanged: _onText,
                onSubmitted: _add,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration: const InputDecoration(
                  hintText: '#добавить тег',
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ],
        ),
        if (pool.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final s in pool)
                ActionChip(
                  label: Text('#$s'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _add(s),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
