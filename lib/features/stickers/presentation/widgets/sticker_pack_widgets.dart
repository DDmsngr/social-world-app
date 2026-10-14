import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/friendly_error.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../chat/domain/stickers.dart';
import '../../../chat/presentation/widgets/sticker_views.dart';
import '../../sticker_providers.dart';

/// «Добавить» → «Установлен». Повторно поставить нельзя: установленный пак
/// показывает состояние, а не кнопку. Снятый с публикации — не ставится.
class PackInstallButton extends ConsumerStatefulWidget {
  const PackInstallButton({super.key, required this.pack, this.onInstalled});

  final StickerPack pack;
  final VoidCallback? onInstalled;

  @override
  ConsumerState<PackInstallButton> createState() => _PackInstallButtonState();
}

class _PackInstallButtonState extends ConsumerState<PackInstallButton> {
  bool _busy = false;

  Future<void> _install() async {
    setState(() => _busy = true);
    try {
      await ref.read(installedStickerPacksProvider.notifier).install(widget.pack.id);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        // Пак 18+, а возраст не указан (или меньше 18): база отказала.
        // Объясняем и ведём туда, где дату можно указать.
        final adultOnly = widget.pack.adult && error.toString().contains('42501');
        final router = GoRouter.maybeOf(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              adultOnly
                  ? 'Пак 18+. Укажите дату рождения в профиле'
                  : friendlyError(error, fallback: 'Не удалось добавить пак'),
            ),
            action: adultOnly && router != null
                ? SnackBarAction(label: 'Указать', onPressed: () => router.push(Routes.editProfile))
                : null,
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
    widget.onInstalled?.call();
  }

  /// Убрать из своих — тут же, рядом с «Установлен», с возможностью вернуть.
  Future<void> _uninstall() async {
    final installed = ref.read(installedStickerPacksProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await installed.uninstall(widget.pack.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Пак «${widget.pack.title}» убран из ваших стикеров'),
          action: widget.pack.isPublished
              ? SnackBarAction(label: 'Вернуть', onPressed: () => installed.install(widget.pack.id))
              : null,
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось убрать пак'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedStickerPacksProvider).value?.contains(widget.pack.id) ?? false;
    if (installed) {
      // Wrap, а не Row: в карточке магазина на узком телефоне «Убрать» не
      // влезает в строку и переносится, а не вылезает за край.
      return Wrap(
        key: ValueKey('pack-installed-${widget.pack.id}'),
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.success),
              const SizedBox(width: 6),
              Text('Установлен', style: TextStyle(fontSize: 14, color: AppColors.textDim)),
            ],
          ),
          TextButton(
            key: ValueKey('pack-uninstall-${widget.pack.id}'),
            onPressed: _uninstall,
            style: AppButtons.compact,
            child: const Text('Убрать'),
          ),
        ],
      );
    }
    if (!widget.pack.isPublished) {
      return Text('Снят с публикации', style: TextStyle(fontSize: 13, color: AppColors.textFaint));
    }
    return FilledButton(
      key: ValueKey('pack-install-${widget.pack.id}'),
      onPressed: _busy ? null : _install,
      style: AppButtons.compact,
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Добавить'),
    );
  }
}

/// Карточка пака в магазине и в «Моих стикерах»: крупная обложка, название,
/// издатель, число стикеров, полоска первых стикеров и действие справа.
class StickerPackCard extends StatelessWidget {
  const StickerPackCard({
    super.key,
    required this.pack,
    required this.onTap,
    required this.trailing,
  });

  final StickerPack pack;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final preview = pack.stickers.skip(1).take(4).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        key: ValueKey('pack-card-${pack.id}'),
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.ink2,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: StickerImage(
                    url: pack.coverUrl,
                    fallback: pack.stickers.isEmpty ? '' : pack.stickers.first.emoji,
                    size: 68,
                    semanticLabel: 'Обложка пака «${pack.title}»',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${pack.publisher} · ${stickerCountLabel(pack.stickers.length)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.textDim),
                      ),
                      const SizedBox(height: 8),
                      trailing,
                    ],
                  ),
                ),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final s in preview)
                    Expanded(
                      child: Center(
                        child: StickerImage(url: s.thumbUrl, fallback: s.emoji, size: 56),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String stickerCountLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'стикер'
      : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
      ? 'стикера'
      : 'стикеров';
  return '$n $word';
}
