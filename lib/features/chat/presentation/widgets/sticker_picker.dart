import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Стикеры — эмодзи крупным планом, паки перенесены из DDChat. Ни сервера,
/// ни загрузки: в сообщении едет сам символ.
Future<String?> showStickerPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.ink2,
      showDragHandle: true,
      builder: (_) => const _StickerPicker(),
    );

class _StickerPicker extends StatefulWidget {
  const _StickerPicker();

  @override
  State<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<_StickerPicker> {
  int _pack = 0;

  static const _packs = <(String, List<String>)>[
    ('😀', [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂',
      '🙂', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗',
      '🤗', '🤭', '🤫', '🤔', '😏', '😬', '🤥', '😌',
      '😴', '🥱', '😎', '🤓', '🧐', '🥳', '🤯', '😱',
      '😤', '😡', '🤬', '😈', '👿', '💀', '👻', '🤡',
    ]),
    ('❤️', [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
      '🤎', '💔', '❤️‍🔥', '❤️‍🩹', '💖', '💗', '💓', '💞',
      '💕', '💘', '💝', '💟', '🫶', '🤟', '🤙', '💪',
    ]),
    ('🐱', [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
      '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐧',
      '🦅', '🦋', '🐛', '🐝', '🐢', '🐍', '🦎', '🐙',
      '🦈', '🐬', '🐳', '🐠', '🦩', '🦜', '🐓', '🦔',
    ]),
    ('🍕', [
      '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓',
      '🍒', '🍑', '🥭', '🍍', '🍕', '🍔', '🌭', '🍟',
      '🌮', '🌯', '🍣', '🍱', '🍩', '🎂', '🧁', '☕',
      '🍺', '🍷', '🥂', '🧋', '🥤', '🍵', '🧃', '🍾',
    ]),
    ('✨', [
      '✨', '⭐', '🌟', '💫', '🔥', '💥', '🎉', '🎊',
      '🏆', '🥇', '🎯', '🎁', '🎈', '🎀', '🎮', '🕹️',
      '🎵', '🎶', '🎤', '📱', '💻', '🔒', '🔑', '💡',
      '⚡', '🌈', '☀️', '🌙', '⛈️', '❄️', '🌊', '🍀',
    ]),
    ('👋', [
      '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌',
      '👐', '🤲', '🤝', '🙏', '✌️', '🤞', '🤟', '🤘',
      '🤙', '👈', '👉', '👆', '👇', '☝️', '👋', '🤚',
      '✋', '🖖', '👌', '🤌', '💪', '🦾', '✍️', '🫡',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final stickers = _packs[_pack].$2;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.4,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (var i = 0; i < _packs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_packs[i].$1, style: const TextStyle(fontSize: 18)),
                      selected: i == _pack,
                      onSelected: (_) => setState(() => _pack = i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 8,
              padding: const EdgeInsets.all(12),
              children: [
                for (final sticker in stickers)
                  InkResponse(
                    onTap: () => Navigator.of(context).pop(sticker),
                    child: Center(
                      child: Text(sticker, style: const TextStyle(fontSize: 30)),
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
