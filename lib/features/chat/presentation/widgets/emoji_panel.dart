import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/stickers.dart';
import 'sticker_views.dart';

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

/// Панель на месте клавиатуры. Первыми — паки фирменных стикеров (стикер
/// уходит сразу), за ними вкладка «Эмодзи»: полный набор Unicode (около
/// 3600 эмодзи) по категориям, недавние, оттенки кожи, поиск по-русски и
/// кнопка «стереть». Эмодзи вставляются в текст и ничего не отправляют.
///
/// Свои паки работают в двух режимах (переключатель справа): «Эмодзи» —
/// смайл встаёт в текст картинкой размером с букву ([onCustomEmoji]),
/// «Стикеры» — уходит сразу отдельным сообщением ([onSticker]).
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({
    super.key,
    required this.onPick,
    required this.onBackspace,
    this.stickerPacks = const [],
    this.onSticker,
    this.onCustomEmoji,
    this.height = 300,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onBackspace;

  /// Паки стикеров — вкладками перед эмодзи.
  final List<StickerPack> stickerPacks;
  final ValueChanged<Sticker>? onSticker;
  final ValueChanged<Sticker>? onCustomEmoji;
  final double height;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  /// Выбранная вкладка: `pack:<id>` или `emoji`. null — первый пак: свои
  /// стикеры первыми. Ключ, а не номер: паки приходят после первого кадра.
  String? _tab;

  static const _tabsHeight = 44.0;

  /// false — свои паки вставляются в текст как эмодзи, true — уходят
  /// стикерами. Панель открывается кнопкой эмодзи, поэтому сначала — эмодзи.
  bool _stickers = false;

  bool get _stickerMode => _stickers || widget.onCustomEmoji == null;

  void _pickSticker(Sticker sticker) {
    HapticFeedback.selectionClick();
    if (_stickerMode) {
      widget.onSticker?.call(sticker);
    } else {
      widget.onCustomEmoji!(sticker);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packs = [
      for (final pack in widget.stickerPacks)
        if (pack.stickers.isNotEmpty) pack,
    ];
    if (packs.isEmpty) {
      return Container(
        height: widget.height,
        color: AppColors.ink2,
        child: _picker(widget.height),
      );
    }
    final stickerMode = _stickerMode;
    final tab = _tab ?? 'pack:${packs.first.id}';
    StickerPack? pack;
    for (final p in packs) {
      if (tab == 'pack:${p.id}') pack = p;
    }
    // Обычный эмодзи стикером не отправить: в режиме стикеров его вкладки нет.
    if (stickerMode && pack == null) pack = packs.first;

    return Container(
      height: widget.height,
      color: AppColors.ink2,
      child: Column(
        children: [
          SizedBox(
            height: _tabsHeight,
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
                          selected: pack == p,
                          onTap: () => setState(() => _tab = 'pack:${p.id}'),
                          child: StickerImage(
                            asset: p.stickers.first.asset,
                            fallback: p.stickers.first.emoji,
                            size: 28,
                            semanticLabel: 'Пак «${p.title}»',
                          ),
                        ),
                      if (!stickerMode)
                        _Tab(
                          key: const ValueKey('emoji-tab'),
                          selected: pack == null,
                          onTap: () => setState(() => _tab = 'emoji'),
                          child: Icon(
                            Icons.emoji_emotions_outlined,
                            size: 22,
                            semanticLabel: 'Эмодзи',
                            color: pack == null
                                ? AppColors.primaryTint
                                : AppColors.textFaint,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.onCustomEmoji != null)
                  TextButton(
                    key: const ValueKey('panel-mode'),
                    onPressed: () => setState(() => _stickers = !_stickers),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryTint,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(stickerMode ? 'Эмодзи' : 'Стикеры'),
                  ),
                // У своих паков в режиме эмодзи «стереть» нужно здесь: у
                // вкладки обычных эмодзи своя кнопка внутри пикера.
                if (!stickerMode && pack != null)
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
                ? StickerGrid(
                    key: ValueKey('grid-$stickerMode-${pack.id}'),
                    stickers: pack.stickers,
                    onPick: _pickSticker,
                    compact: !stickerMode,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) =>
                        _picker(constraints.maxHeight),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _picker(double pickerHeight) {
    final onPick = widget.onPick;
    final onBackspace = widget.onBackspace;
    return EmojiPicker(
      onEmojiSelected: (category, emoji) {
        HapticFeedback.selectionClick();
        onPick(emoji.emoji);
      },
      onBackspacePressed: onBackspace,
      config: Config(
        height: pickerHeight,
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
        width: 48,
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
