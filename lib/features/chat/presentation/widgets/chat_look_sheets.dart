import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/theme/app_colors.dart';
import '../chat_looks.dart';
import '../providers/chat_settings_providers.dart';

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// «Звук чата»: выбор из нескольких звуков, с прослушиванием. Действует на
/// уведомления этого чата, когда приложение свёрнуто.
Future<void> showChatSoundSheet(BuildContext context, String conversationId) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.ink2,
    builder: (_) => _SoundSheet(conversationId: conversationId),
  );
}

class _SoundSheet extends ConsumerWidget {
  const _SoundSheet({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = chatSettingsOf(ref, conversationId);

    Future<void> pick(String? id) async {
      if (id != null) ChatSoundPreview.play(id);
      try {
        await saveChatLook(ref, conversationId, sound: id, wallpaper: settings.wallpaper);
      } catch (error) {
        AppLog.add('Звук чата не сохранился: $error');
        if (context.mounted) _toast(context, friendlyError(error, fallback: 'Не удалось сохранить'));
      }
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Звук чата', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Звучит, когда в этот чат приходит сообщение, а приложение свёрнуто.',
                style: TextStyle(fontSize: 13, color: AppColors.textDim),
              ),
            ),
          ),
          RadioGroup<String?>(
            groupValue: settings.sound,
            onChanged: pick,
            child: Column(
              children: [
                const RadioListTile<String?>(value: null, title: Text('Стандартный')),
                for (final s in chatSounds)
                  RadioListTile<String?>(
                    value: s.id,
                    title: Text(s.label),
                    secondary: IconButton(
                      tooltip: 'Прослушать',
                      icon: const Icon(Icons.play_arrow_rounded),
                      onPressed: () => ChatSoundPreview.play(s.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// «Фон чата». В личном чате можно предложить тот же фон собеседнику: он
/// увидит плашку и примет или откажется.
Future<void> showChatWallpaperSheet(
  BuildContext context,
  String conversationId, {
  required bool direct,
  required String peerName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.ink2,
    builder: (_) => _WallpaperSheet(conversationId: conversationId, direct: direct, peerName: peerName),
  );
}

class _WallpaperSheet extends ConsumerStatefulWidget {
  const _WallpaperSheet({required this.conversationId, required this.direct, required this.peerName});

  final String conversationId;
  final bool direct;
  final String peerName;

  @override
  ConsumerState<_WallpaperSheet> createState() => _WallpaperSheetState();
}

class _WallpaperSheetState extends ConsumerState<_WallpaperSheet> {
  var _offer = true;
  var _busy = false;

  Future<void> _pick(String? id) async {
    if (_busy) return;
    setState(() => _busy = true);
    final settings = chatSettingsOf(ref, widget.conversationId);
    try {
      if (id != null && widget.direct && _offer) {
        await offerChatWallpaper(ref, widget.conversationId, id);
        if (mounted) _toast(context, '${widget.peerName} увидит предложение');
      } else {
        await saveChatLook(ref, widget.conversationId, sound: settings.sound, wallpaper: id);
      }
    } catch (error) {
      AppLog.add('Фон чата не сохранился: $error');
      if (mounted) _toast(context, friendlyError(error, fallback: 'Не удалось сохранить'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = chatSettingsOf(ref, widget.conversationId).wallpaper;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Фон чата', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _Swatch(label: 'Обычный', selected: current == null, onTap: () => _pick(null)),
                for (final w in chatWallpapers)
                  _Swatch(
                    label: w.label,
                    gradient: w.gradient,
                    selected: current == w.id,
                    onTap: () => _pick(w.id),
                  ),
              ],
            ),
            if (widget.direct) ...[
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _offer,
                onChanged: (v) => setState(() => _offer = v),
                title: Text('Предложить и ${widget.peerName}'),
                subtitle: const Text('Он решит сам: принять этот фон или оставить свой'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.selected, required this.onTap, this.gradient});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: gradient,
                  color: gradient == null ? AppColors.card : null,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.hair,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: gradient == null
                    ? Icon(Icons.block, color: AppColors.textFaint, size: 22)
                    : selected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плашка над перепиской: собеседник выбрал фон «для двоих».
class WallpaperOfferBar extends ConsumerWidget {
  const WallpaperOfferBar({super.key, required this.conversationId, required this.peerName});

  final String conversationId;
  final String peerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(wallpaperOfferProvider(conversationId)).value;
    if (offer == null) return const SizedBox.shrink();
    final wallpaper = chatWallpaperById(offer.wallpaper);

    Future<void> answer(bool accept) async {
      try {
        await respondWallpaperOffer(ref, offer.id, accept: accept);
        ref.invalidate(wallpaperOfferProvider(conversationId));
      } catch (error) {
        AppLog.add('Ответ на предложение фона: $error');
        if (context.mounted) _toast(context, friendlyError(error, fallback: 'Не удалось ответить'));
      }
    }

    return Material(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: wallpaper?.gradient,
                color: wallpaper == null ? AppColors.ink2 : null,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$peerName предлагает фон «${chatWallpaperLabel(offer.wallpaper)}»',
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            TextButton(onPressed: () => answer(false), child: const Text('Нет')),
            FilledButton(
              onPressed: () => answer(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Принять'),
            ),
          ],
        ),
      ),
    );
  }
}
