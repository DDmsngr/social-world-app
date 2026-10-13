import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../chat/domain/stickers.dart';
import '../sticker_providers.dart';
import 'widgets/sticker_pack_widgets.dart';

/// Мои стикеры: установленные паки — ровно те, что видны в панели
/// переписки. Убрать пак — только из своей коллекции: из магазина он не
/// пропадает, отправленные стикеры остаются на месте.
class MyStickersScreen extends ConsumerWidget {
  const MyStickersScreen({super.key});

  Future<void> _remove(BuildContext context, WidgetRef ref, StickerPack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Убрать «${pack.title}»?'),
        content: const Text(
          'Стикеры пропадут из панели. Уже отправленные останутся в переписке, '
          'а пак можно снова добавить из магазина.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Отмена')),
          TextButton(
            key: const ValueKey('confirm-remove-pack'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(installedStickerPacksProvider.notifier).uninstall(pack.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось убрать пак'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedStickerPacksProvider);
    final catalog = ref.watch(stickerCatalogProvider);
    final packs = ref.watch(myStickerPacksProvider);

    Future<void> refresh() => Future.wait([
      ref.read(stickerCatalogProvider.notifier).refresh(),
      ref.read(installedStickerPacksProvider.notifier).refresh(),
    ]);

    final Widget body;
    if (installed.value == null || catalog.value == null) {
      body = installed.hasError || catalog.hasError
          ? StateMessage.error(
              title: 'Стикеры не загрузились',
              onAction: () {
                ref.invalidate(installedStickerPacksProvider);
                ref.invalidate(stickerCatalogProvider);
              },
            )
          : const LoadingView();
    } else if (packs.isEmpty) {
      body = StateMessage(
        icon: Icons.sticky_note_2_outlined,
        title: 'Здесь будут ваши стикеры',
        text: 'Добавьте паки из магазина — их стикеры появятся в переписке.',
        actionLabel: 'Открыть магазин',
        onAction: () => context.push(Routes.stickerStore),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: AppSpacing.page(context),
          children: [
            for (final pack in packs)
              StickerPackCard(
                pack: pack,
                onTap: () => context.push(Routes.stickerPack(pack.id)),
                trailing: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey('remove-pack-${pack.id}'),
                    onPressed: () => _remove(context, ref, pack),
                    style: AppButtons.compact,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Убрать'),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои стикеры'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('open-sticker-store'),
            onPressed: () => context.push(Routes.stickerStore),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Магазин'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}
