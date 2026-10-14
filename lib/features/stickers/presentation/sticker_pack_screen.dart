import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../chat/domain/stickers.dart';
import '../../chat/presentation/widgets/sticker_views.dart';
import '../sticker_providers.dart';
import 'widgets/sticker_pack_widgets.dart';

/// Страница пака: все стикеры сеткой, добавить в свои или убрать. Открывается
/// из магазина, из «Моих стикеров» и по стикеру из переписки — тогда
/// [highlight] (ключ стикера) показан сверху и подсвечен в сетке, чтобы было
/// видно, какой именно стикер привёл сюда.
class StickerPackScreen extends ConsumerStatefulWidget {
  const StickerPackScreen({super.key, required this.packId, this.highlight});

  final String packId;
  final String? highlight;

  @override
  ConsumerState<StickerPackScreen> createState() => _StickerPackScreenState();
}

class _StickerPackScreenState extends ConsumerState<StickerPackScreen> {
  final _highlightKey = GlobalKey();
  bool _scrolled = false;
  bool _refreshedForMissing = false;

  void _scrollToHighlight() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _highlightKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, alignment: 0.4, duration: const Duration(milliseconds: 300));
      }
    });
  }

  /// Пришли по стикеру из переписки — предлагаем вернуться туда.
  void _installed(StickerPack pack) {
    if (!mounted) return;
    final fromChat = widget.highlight != null && Navigator.of(context).canPop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // С кнопкой плашка по умолчанию не уходит сама.
        persist: false,
        duration: const Duration(seconds: 3),
        content: Text('Пак «${pack.title}» в ваших стикерах'),
        action: fromChat
            ? SnackBarAction(label: 'К переписке', onPressed: () => Navigator.of(context).maybePop())
            : SnackBarAction(label: 'Мои стикеры', onPressed: () => context.push(Routes.myStickers)),
      ),
    );
  }

  void _preview(Sticker sticker) {
    showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        backgroundColor: AppColors.ink2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StickerImage(url: sticker.imageUrl, fallback: sticker.emoji, size: 220, semanticLabel: sticker.title),
              const SizedBox(height: 12),
              Text(sticker.title, style: TextStyle(fontSize: 16, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(visibleStickerCatalogProvider);
    final pack = catalog.value?.pack(widget.packId);

    final Widget body;
    if (pack != null) {
      body = _content(pack);
    } else if (catalog.hasError) {
      body = StateMessage.error(
        title: 'Пак не загрузился',
        onAction: () => ref.invalidate(stickerCatalogProvider),
      );
    } else if (catalog.value != null) {
      // Пака нет в сохранённом каталоге — может, он новый: один раз
      // спрашиваем сервер.
      if (!_refreshedForMissing) {
        _refreshedForMissing = true;
        Future(() => ref.read(stickerCatalogProvider.notifier).refresh());
        body = const LoadingView();
      } else {
        body = StateMessage(
          icon: Icons.sticky_note_2_outlined,
          title: 'Пак не найден',
          text: 'Возможно, его ещё не опубликовали.',
          actionLabel: 'В магазин',
          onAction: () => context.go(Routes.stickerStore),
        );
      }
    } else {
      body = const LoadingView();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pack?.title ?? 'Стикеры'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.stickerStore),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: body,
    );
  }

  Widget _content(StickerPack pack) {
    Sticker? highlighted;
    for (final s in pack.stickers) {
      if (s.key == widget.highlight) highlighted = s;
    }
    if (highlighted != null) _scrollToHighlight();

    return SingleChildScrollView(
      padding: AppSpacing.page(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted != null) _HighlightBanner(sticker: highlighted, pack: pack),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.ink2,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: StickerImage(url: pack.coverUrl, size: 88, semanticLabel: 'Обложка пака «${pack.title}»'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text(
                      [pack.publisher, stickerCountLabel(pack.stickers.length), ?pack.category].join(' · '),
                      style: TextStyle(fontSize: 13, color: AppColors.textDim),
                    ),
                    const SizedBox(height: 12),
                    PackInstallButton(pack: pack, onInstalled: () => _installed(pack)),
                  ],
                ),
              ),
            ],
          ),
          if (pack.description != null) ...[
            const SizedBox(height: 14),
            Text(pack.description!, style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.text)),
          ],
          if (!pack.isPublished) ...[
            const SizedBox(height: 12),
            Text(
              'Пак снят с публикации: добавить его нельзя, но его стикеры по-прежнему видны в переписке.',
              style: TextStyle(fontSize: 13, color: AppColors.textDim),
            ),
          ],
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final s in pack.stickers)
                _StickerCell(
                  key: s == highlighted ? _highlightKey : ValueKey('pack-sticker-${s.id}'),
                  sticker: s,
                  highlighted: s == highlighted,
                  onTap: () => _preview(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Тот самый стикер из переписки — крупно над паком.
class _HighlightBanner extends ConsumerWidget {
  const _HighlightBanner({required this.sticker, required this.pack});

  final Sticker sticker;
  final StickerPack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedStickerPacksProvider).value?.contains(pack.id) ?? false;
    return Container(
      key: const ValueKey('sticker-highlight-banner'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryTint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.primaryTint.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          StickerImage(url: sticker.imageUrl, fallback: sticker.emoji, size: 96, semanticLabel: sticker.title),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Стикер «${sticker.title}»', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 4),
                Text(
                  installed
                      ? 'Из пака «${pack.title}». Он уже у вас: стикер можно отправлять.'
                      : 'Из пака «${pack.title}». Добавьте пак, чтобы отправлять его стикеры.',
                  style: TextStyle(fontSize: 13, color: AppColors.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerCell extends StatelessWidget {
  const _StickerCell({super.key, required this.sticker, required this.highlighted, required this.onTap});

  final Sticker sticker;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: highlighted
            ? BoxDecoration(
                color: AppColors.primaryTint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryTint, width: 2),
              )
            : null,
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(
          builder: (context, box) => StickerImage(
            url: sticker.thumbUrl,
            fallback: sticker.emoji,
            size: box.maxWidth,
            semanticLabel: highlighted ? 'Стикер «${sticker.title}», выделен' : 'Стикер «${sticker.title}»',
          ),
        ),
      ),
    );
  }
}
