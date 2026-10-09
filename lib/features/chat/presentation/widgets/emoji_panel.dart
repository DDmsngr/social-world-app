import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/stickers.dart';
import 'sticker_views.dart';

/// Эмодзи для поля ввода: вставляются в текст на место курсора и ничего не
/// отправляют. Раньше на этом месте были «стикеры» — те же эмодзи, которые
/// улетали отдельным сообщением, и человек терял то, что хотел написать.
const emojiCategories = <(String, List<String>)>[
  (
    '😀',
    [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '🤗',
      '🤭',
      '🤫',
      '🤔',
      '😏',
      '😬',
      '🤥',
      '😌',
      '😴',
      '🥱',
      '😎',
      '🤓',
      '🧐',
      '🥳',
      '🤯',
      '😱',
      '😤',
      '😡',
      '🤬',
      '😈',
      '👿',
      '💀',
      '👻',
      '🤡',
    ],
  ),
  (
    '❤️',
    [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❤️‍🔥',
      '❤️‍🩹',
      '💖',
      '💗',
      '💓',
      '💞',
      '💕',
      '💘',
      '💝',
      '💟',
      '🫶',
      '🤟',
      '🤙',
      '💪',
    ],
  ),
  (
    '🐱',
    [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐧',
      '🦅',
      '🦋',
      '🐛',
      '🐝',
      '🐢',
      '🐍',
      '🦎',
      '🐙',
      '🦈',
      '🐬',
      '🐳',
      '🐠',
      '🦩',
      '🦜',
      '🐓',
      '🦔',
    ],
  ),
  (
    '🍕',
    [
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🍕',
      '🍔',
      '🌭',
      '🍟',
      '🌮',
      '🌯',
      '🍣',
      '🍱',
      '🍩',
      '🎂',
      '🧁',
      '☕',
      '🍺',
      '🍷',
      '🥂',
      '🧋',
      '🥤',
      '🍵',
      '🧃',
      '🍾',
    ],
  ),
  (
    '✨',
    [
      '✨',
      '⭐',
      '🌟',
      '💫',
      '🔥',
      '💥',
      '🎉',
      '🎊',
      '🏆',
      '🥇',
      '🎯',
      '🎁',
      '🎈',
      '🎀',
      '🎮',
      '🕹️',
      '🎵',
      '🎶',
      '🎤',
      '📱',
      '💻',
      '🔒',
      '🔑',
      '💡',
      '⚡',
      '🌈',
      '☀️',
      '🌙',
      '⛈️',
      '❄️',
      '🌊',
      '🍀',
    ],
  ),
  (
    '👋',
    [
      '👍',
      '👎',
      '👊',
      '✊',
      '🤛',
      '🤜',
      '👏',
      '🙌',
      '👐',
      '🤲',
      '🤝',
      '🙏',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '👇',
      '☝️',
      '👋',
      '🤚',
      '✋',
      '🖖',
      '👌',
      '🤌',
      '💪',
      '🦾',
      '✍️',
      '🫡',
    ],
  ),
];

/// Вставляет [insert] вместо выделения (или в позицию курсора). Без курсора —
/// в конец: поле могло ни разу не получить фокус.
TextEditingValue insertAtSelection(TextEditingValue value, String insert) {
  final text = value.text;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : text.length;
  return TextEditingValue(
    text: text.replaceRange(start, end, insert),
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

/// «Стереть» с панели: удаляет выделение или один символ перед курсором
/// целиком — эмодзи из нескольких кодовых точек (флаги, 👍🏽) не рвётся.
TextEditingValue deleteBeforeSelection(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : text.length;
  if (start != end) {
    return TextEditingValue(
      text: text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }
  if (start == 0) return value;
  final before = text.substring(0, start).characters.skipLast(1).toString();
  return TextEditingValue(
    text: before + text.substring(start),
    selection: TextSelection.collapsed(offset: before.length),
  );
}

/// Панель на месте клавиатуры: недавние, категории эмодзи, паки стикеров,
/// кнопка «стереть». Эмодзи вставляются в текст, стикер уходит сразу.
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({
    super.key,
    required this.onPick,
    required this.onBackspace,
    this.stickerPacks = const [],
    this.onSticker,
    this.height = 280,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onBackspace;

  /// Паки стикеров — вкладками после эмодзи.
  final List<StickerPack> stickerPacks;
  final ValueChanged<Sticker>? onSticker;
  final double height;

  /// Недавние живут, пока запущено приложение, — этого хватает, чтобы
  /// любимые эмодзи были под рукой без лишней записи на диск.
  static final recent = <String>[];

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  /// Выбранная вкладка: `pack:<id>`, `recent` или `emoji:<номер>`. null —
  /// по умолчанию: свои стикеры первыми, без них — недавние или первая
  /// категория эмодзи. Ключ, а не номер: паки приходят после первого кадра,
  /// и номера вкладок за ними сдвинулись бы.
  String? _tab;

  void _pick(String emoji) {
    HapticFeedback.selectionClick();
    EmojiPanel.recent
      ..remove(emoji)
      ..insert(0, emoji);
    if (EmojiPanel.recent.length > 32) EmojiPanel.recent.removeLast();
    widget.onPick(emoji);
  }

  void _pickSticker(Sticker sticker) {
    HapticFeedback.selectionClick();
    widget.onSticker?.call(sticker);
  }

  @override
  Widget build(BuildContext context) {
    final packs = [
      for (final pack in widget.stickerPacks)
        if (pack.stickers.isNotEmpty) pack,
    ];
    // Вкладки по порядку: паки стикеров, недавние, категории эмодзи.
    final tab =
        _tab ??
        (packs.isNotEmpty
            ? 'pack:${packs.first.id}'
            : EmojiPanel.recent.isEmpty
            ? 'emoji:0'
            : 'recent');
    StickerPack? pack;
    for (final p in packs) {
      if (tab == 'pack:${p.id}') pack = p;
    }
    final category = tab.startsWith('emoji:')
        ? int.tryParse(tab.substring(6))
        : null;
    final emojis = pack != null
        ? const <String>[]
        : category != null && category < emojiCategories.length
        ? emojiCategories[category].$2
        : EmojiPanel.recent;

    return Container(
      height: widget.height,
      color: AppColors.ink2,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final p in packs)
                        _Tab(
                          key: ValueKey('sticker-pack-${p.id}'),
                          selected: tab == 'pack:${p.id}',
                          onTap: () => setState(() => _tab = 'pack:${p.id}'),
                          child: StickerImage(
                            asset: p.stickers.first.asset,
                            fallback: p.stickers.first.emoji,
                            size: 28,
                            semanticLabel: 'Стикеры «${p.title}»',
                          ),
                        ),
                      _Tab(
                        key: const ValueKey('emoji-tab-recent'),
                        selected: tab == 'recent',
                        onTap: () => setState(() => _tab = 'recent'),
                        child: Icon(
                          Icons.schedule,
                          size: 20,
                          color: tab == 'recent'
                              ? AppColors.primaryTint
                              : AppColors.textFaint,
                        ),
                      ),
                      for (var i = 0; i < emojiCategories.length; i++)
                        _Tab(
                          key: ValueKey('emoji-tab-$i'),
                          selected: tab == 'emoji:$i',
                          onTap: () => setState(() => _tab = 'emoji:$i'),
                          child: Text(
                            emojiCategories[i].$1,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onBackspace,
                  tooltip: 'Стереть',
                  icon: Icon(
                    Icons.backspace_outlined,
                    color: AppColors.textDim,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hair),
          Expanded(
            child: pack != null
                ? StickerGrid(stickers: pack.stickers, onPick: _pickSticker)
                : emojis.isEmpty
                ? Center(
                    child: Text(
                      'Здесь появятся недавние',
                      style: TextStyle(color: AppColors.textFaint),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 8,
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final emoji in emojis)
                        InkResponse(
                          onTap: () => _pick(emoji),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primaryTint : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Сколько эмодзи в сообщении, если кроме них там ничего нет (до трёх).
/// Такие сообщения рисуются крупно и без пузыря, как в Telegram. 0 — это
/// обычный текст.
int emojiOnlyCount(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return 0;
  var count = 0;
  for (final grapheme in trimmed.characters) {
    if (grapheme.trim().isEmpty) continue;
    if (!_emoji.hasMatch(grapheme)) return 0;
    if (++count > 3) return 0;
  }
  return count;
}

// Анализатор проверяет выражение без флага unicode и не знает \p{…};
// в рантайме оно валидно — это покрыто тестом emoji_panel_test.
final _emoji = RegExp(
  // ignore: valid_regexps
  r'\p{Extended_Pictographic}|\p{Regional_Indicator}|\u20E3',
  unicode: true,
);
