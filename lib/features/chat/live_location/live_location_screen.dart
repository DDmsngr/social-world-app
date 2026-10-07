import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/location/device_position.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'live_location.dart';
import 'live_map.dart';

typedef _Person = ({String name, String? avatar});

/// Имена и аватарки тех, кто транслирует (ключ — список id через запятую).
final _peopleProvider = FutureProvider.autoDispose.family<Map<String, _Person>, String>((ref, ids) async {
  if (!Env.isConfigured || ids.isEmpty) return const {};
  final rows = await Supabase.instance.client
      .from('profiles')
      .select('id, display_name, avatar_url')
      .inFilter('id', ids.split(','));
  return {
    for (final r in rows)
      r['id'] as String: (name: (r['display_name'] as String?) ?? 'Без имени', avatar: r['avatar_url'] as String?),
  };
});

/// Выбор длительности: 15 мин / 30 мин / час / пока не выключу. Возвращает
/// минуты, `-1` — «пока не выключу», null — передумали.
Future<int?> pickLiveDuration(BuildContext context) => showModalBottomSheet<int>(
  context: context,
  useRootNavigator: true,
  backgroundColor: AppColors.ink2,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Собеседники будут видеть на карте, где вы, пока идёт трансляция. '
            'Выключить можно в любой момент.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ),
        for (final (minutes, label) in const [(15, '15 минут'), (30, '30 минут'), (60, '1 час'), (-1, 'Пока не выключу')])
          ListTile(
            leading: Icon(Icons.share_location, color: AppColors.geo),
            title: Text(label),
            onTap: () => Navigator.of(context).pop(minutes),
          ),
      ],
    ),
  ),
);

/// Начать трансляцию в чате: длительность → разрешение → первая точка.
/// true — пошла.
Future<bool> startLiveSharing(BuildContext context, WidgetRef ref, String conversationId) async {
  final minutes = await pickLiveDuration(context);
  if (minutes == null || !context.mounted) return false;
  final position = await requestDevicePosition(context);
  if (!context.mounted) return false;
  final first = position.position;
  if (first == null) {
    final message = position.message;
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
  try {
    await ref.read(liveLocationSharerProvider).start(conversationId, minutes < 0 ? null : minutes, first);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось начать трансляцию'))),
      );
    }
    return false;
  }
}

/// Карта трансляции чата: кто где, сколько осталось, своя — с кнопкой «Остановить».
class LiveLocationScreen extends ConsumerStatefulWidget {
  const LiveLocationScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends ConsumerState<LiveLocationScreen> {
  var _frame = 0;

  @override
  Widget build(BuildContext context) {
    final shares = ref.watch(liveSharesProvider(widget.conversationId)).value ?? const <LiveShare>[];
    final me = ref.watch(currentUserProvider)?.id;
    final ids = (shares.map((s) => s.userId).toSet().toList()..sort()).join(',');
    final people = ref.watch(_peopleProvider(ids)).value ?? const <String, _Person>{};
    final sharer = ref.watch(liveLocationSharerProvider);
    final now = DateTime.now();

    final markers = [
      for (final s in shares)
        if (s.point != null)
          LiveMapMarker(
            latitude: s.point!.lat,
            longitude: s.point!.lng,
            label: s.userId == me ? 'Вы' : people[s.userId]?.name ?? '',
            avatarUrl: people[s.userId]?.avatar,
            me: s.userId == me,
          ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Геопозиция'),
        actions: [
          if (markers.length > 1)
            IconButton(
              tooltip: 'Показать всех',
              onPressed: () => setState(() => _frame++),
              icon: const Icon(Icons.fit_screen_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: markers.isEmpty
                ? Center(
                    child: Text(
                      shares.isEmpty ? 'Сейчас никто не транслирует геопозицию' : 'Ждём первую точку…',
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  )
                : LiveMap(markers: markers, frameKey: _frame),
          ),
          SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: sharer,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in shares)
                    ListTile(
                      leading: UserAvatar(
                        url: people[s.userId]?.avatar,
                        name: people[s.userId]?.name ?? '',
                        userId: s.userId,
                        radius: 20,
                      ),
                      title: Text(s.userId == me ? 'Вы' : people[s.userId]?.name ?? ''),
                      subtitle: Text('${liveRemainingLabel(s, now)} · ${liveUpdatedLabel(s.updatedAt, now)}'),
                      trailing: s.userId == me
                          ? TextButton(
                              onPressed: () => sharer.stop(widget.conversationId),
                              child: Text('Остановить', style: TextStyle(color: AppColors.danger)),
                            )
                          : null,
                    ),
                  if (!sharer.isSharing(widget.conversationId))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => startLiveSharing(context, ref, widget.conversationId),
                          icon: const Icon(Icons.share_location),
                          label: const Text('Транслировать мою геопозицию'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
