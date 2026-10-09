import 'package:flutter/material.dart';

import '../../domain/stickers.dart';

/// Картинка стикера из ассетов. Если картинки нет (стикер из версии новее
/// этой), рисуется эмодзи-заменитель.
class StickerImage extends StatelessWidget {
  const StickerImage({
    super.key,
    required this.asset,
    this.fallback = '',
    this.size = 148,
    this.semanticLabel,
  });

  final String asset;
  final String fallback;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Декодируем сразу в нужном размере: 512×512 на каждый стикер в сетке
    // панели — лишняя память.
    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.asset(
      asset,
      width: size,
      height: size,
      cacheWidth: cache,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            fallback.isEmpty ? '🙂' : fallback,
            style: TextStyle(fontSize: size * 0.4, height: 1.1),
          ),
        ),
      ),
    );
  }
}

/// Полоса стикеров над полем ввода: человек печатает «любовь» — здесь
/// стикеры про любовь, нажатие отправляет стикер.
class StickerSuggestions extends StatelessWidget {
  const StickerSuggestions({
    super.key,
    required this.stickers,
    required this.onPick,
  });

  final List<Sticker> stickers;
  final ValueChanged<Sticker> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: stickers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final sticker = stickers[i];
          return InkResponse(
            key: ValueKey('sticker-suggestion-${sticker.id}'),
            onTap: () => onPick(sticker),
            radius: 36,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: StickerImage(
                asset: sticker.asset,
                fallback: sticker.emoji,
                size: 64,
                semanticLabel: 'Стикер «${sticker.title}»',
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Сетка одного пака в панели: крупно — стикеры, [compact] — свои эмодзи
/// (мельче и плотнее, как обычные эмодзи).
class StickerGrid extends StatelessWidget {
  const StickerGrid({
    super.key,
    required this.stickers,
    required this.onPick,
    this.compact = false,
  });

  final List<Sticker> stickers;
  final ValueChanged<Sticker> onPick;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: compact ? 7 : 4,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (final sticker in stickers)
          InkResponse(
            key: ValueKey('sticker-${sticker.id}'),
            onTap: () => onPick(sticker),
            child: StickerImage(
              asset: sticker.asset,
              fallback: sticker.emoji,
              size: compact ? 40 : 72,
              semanticLabel: compact
                  ? 'Эмодзи «${sticker.title}»'
                  : 'Стикер «${sticker.title}»',
            ),
          ),
      ],
    );
  }
}

/// Свои эмодзи в тексте сообщения — картинками на месте эмодзи-заменителей
/// (для [LinkText.inline]). Отметки, которые не сходятся с текстом,
/// пропускаются: там остаётся обычный эмодзи.
List<({int start, int end, InlineSpan span})> customEmojiInlines(
  String text,
  List<CustomEmoji> emoji, {
  required double size,
}) => [
  for (final e in validCustomEmoji(text, emoji))
    if (stickerAsset(e.sticker) case final asset?)
      (
        start: e.offset,
        end: e.end,
        span: WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: StickerImage(asset: asset, fallback: e.text, size: size),
        ),
      ),
];

/// Поле ввода со своими эмодзи: каждый — один символ-заместитель
/// ([StickerCatalog.inlineChar]), который рисуется картинкой размером с
/// букву. Курсор и «стереть» работают с ним как с обычным символом.
class InlineEmojiController extends TextEditingController {
  StickerCatalog? catalog;

  bool _hasInline(StickerCatalog catalog) {
    for (final unit in text.codeUnits) {
      if (catalog.byInlineCode(unit) != null) return true;
    }
    return false;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final catalog = this.catalog;
    if (catalog == null || !_hasInline(catalog)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final size = (style?.fontSize ?? 16) * 1.35;
    final children = <InlineSpan>[];
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      final sticker = catalog.byInlineCode(unit);
      if (sticker == null) {
        buffer.writeCharCode(unit);
        continue;
      }
      if (buffer.isNotEmpty) {
        children.add(TextSpan(text: buffer.toString()));
        buffer.clear();
      }
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: StickerImage(
            asset: sticker.asset,
            fallback: sticker.emoji,
            size: size,
          ),
        ),
      );
    }
    if (buffer.isNotEmpty) children.add(TextSpan(text: buffer.toString()));
    return TextSpan(style: style, children: children);
  }
}
