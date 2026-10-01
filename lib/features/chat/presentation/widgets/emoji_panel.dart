import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

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

/// Панель на месте клавиатуры: недавние, категории, кнопка «стереть».
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({
    super.key,
    required this.onPick,
    required this.onBackspace,
    this.height = 280,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onBackspace;
  final double height;

  /// Недавние живут, пока запущено приложение, — этого хватает, чтобы
  /// любимые эмодзи были под рукой без лишней записи на диск.
  static final recent = <String>[];

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  late int _tab = EmojiPanel.recent.isEmpty ? 1 : 0;

  void _pick(String emoji) {
    HapticFeedback.selectionClick();
    EmojiPanel.recent
      ..remove(emoji)
      ..insert(0, emoji);
    if (EmojiPanel.recent.length > 32) EmojiPanel.recent.removeLast();
    widget.onPick(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final emojis = _tab == 0 ? EmojiPanel.recent : emojiCategories[_tab - 1].$2;

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
                      _Tab(
                        selected: _tab == 0,
                        onTap: () => setState(() => _tab = 0),
                        child: Icon(
                          Icons.schedule,
                          size: 20,
                          color: _tab == 0
                              ? AppColors.primaryTint
                              : AppColors.textFaint,
                        ),
                      ),
                      for (var i = 0; i < emojiCategories.length; i++)
                        _Tab(
                          selected: _tab == i + 1,
                          onTap: () => setState(() => _tab = i + 1),
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
            child: emojis.isEmpty
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
