import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

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

/// Панель эмодзи на месте клавиатуры: полный набор Unicode (около 3600
/// эмодзи) по категориям, недавние, оттенки кожи, поиск по-русски и кнопка
/// «стереть». Эмодзи вставляются в текст и ничего не отправляют.
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({
    super.key,
    required this.onPick,
    required this.onBackspace,
    this.height = 300,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onBackspace;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: AppColors.ink2,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          HapticFeedback.selectionClick();
          onPick(emoji.emoji);
        },
        onBackspacePressed: onBackspace,
        config: Config(
          height: height,
          locale: const Locale('ru'),
          // Эмодзи, которых нет в шрифте телефона, не показываем пустыми
          // квадратами.
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 30,
            backgroundColor: AppColors.ink2,
            recentsLimit: 40,
            gridPadding: const EdgeInsets.symmetric(horizontal: 6),
            noRecents: Text(
              'Здесь появятся недавние',
              style: TextStyle(fontSize: 15, color: AppColors.textFaint),
              textAlign: TextAlign.center,
            ),
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: AppColors.ink2,
            indicatorColor: AppColors.primaryTint,
            iconColor: AppColors.textFaint,
            iconColorSelected: AppColors.primaryTint,
            backspaceColor: AppColors.primaryTint,
            dividerColor: AppColors.hair,
            tabBarHeight: 44,
          ),
          skinToneConfig: const SkinToneConfig(),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: AppColors.ink2,
            buttonColor: AppColors.card,
            buttonIconColor: AppColors.textDim,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: AppColors.ink2,
            buttonIconColor: AppColors.textDim,
            hintText: 'Поиск эмодзи',
            inputTextStyle: TextStyle(color: AppColors.text, fontSize: 16),
            hintTextStyle: TextStyle(color: AppColors.textFaint, fontSize: 16),
          ),
        ),
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
