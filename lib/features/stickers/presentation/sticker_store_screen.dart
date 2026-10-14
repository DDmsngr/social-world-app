import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../chat/domain/stickers.dart';
import '../sticker_providers.dart';
import 'widgets/sticker_pack_widgets.dart';

/// Магазин стикеров: все опубликованные паки, поиск по названию и
/// категории. Каталог приходит с сервера (sticker_catalog), состояние
/// «установлен» — из коллекции пользователя в базе.
class StickerStoreScreen extends ConsumerStatefulWidget {
  const StickerStoreScreen({super.key});

  @override
  ConsumerState<StickerStoreScreen> createState() => _StickerStoreScreenState();
}

class _StickerStoreScreenState extends ConsumerState<StickerStoreScreen> {
  final _query = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(stickerCatalogProvider.notifier).refresh(),
      ref.read(installedStickerPacksProvider.notifier).refresh(),
    ]);
  }

  bool _matches(StickerPack pack) {
    if (_category != null && pack.category != _category) return false;
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return pack.title.toLowerCase().contains(q) ||
        (pack.category?.toLowerCase().contains(q) ?? false) ||
        (pack.description?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(visibleStickerCatalogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Стикеры'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.chats),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('open-my-stickers'),
            onPressed: () => context.push(Routes.myStickers),
            icon: const Icon(Icons.collections_bookmark_outlined, size: 18),
            label: const Text('Мои'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: catalog.value != null
          ? _content(catalog.value!)
          : catalog.hasError
          ? StateMessage.error(
              title: 'Магазин не загрузился',
              onAction: () => ref.invalidate(stickerCatalogProvider),
            )
          : const LoadingView(),
    );
  }

  Widget _content(StickerCatalog catalog) {
    final published = [for (final p in catalog.packs) if (p.isPublished && p.stickers.isNotEmpty) p];
    if (published.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            StateMessage(
              icon: Icons.sticky_note_2_outlined,
              title: 'Стикерпаков пока нет',
              text: 'Скоро здесь появятся первые паки.',
            ),
          ],
        ),
      );
    }
    final categories = catalog.categories;
    final shown = published.where(_matches).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: AppSpacing.page(context),
        children: [
          TextField(
            key: const ValueKey('sticker-store-search'),
            controller: _query,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Название или категория',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_query.clear),
                      tooltip: 'Очистить',
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          if (categories.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('Все', _category == null, () => setState(() => _category = null)),
                  for (final c in categories)
                    _chip(c, _category == c, () => setState(() => _category = _category == c ? null : c)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: StateMessage(
                icon: Icons.search_off,
                title: 'Ничего не нашлось',
                actionLabel: 'Сбросить поиск',
                onAction: () => setState(() {
                  _query.clear();
                  _category = null;
                }),
              ),
            ),
          for (final pack in shown)
            StickerPackCard(
              pack: pack,
              onTap: () => context.push(Routes.stickerPack(pack.id)),
              trailing: PackInstallButton(pack: pack),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryTint.withValues(alpha: 0.16),
      showCheckmark: false,
    ),
  );
}
