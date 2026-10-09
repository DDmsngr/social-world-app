import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../feed/domain/entities/post.dart';
import '../../feed/domain/entities/publish_settings.dart';
import '../../feed/presentation/providers/feed_providers.dart';
import 'providers/route_recorder.dart';
import 'providers/routes_providers.dart';
import 'widgets/route_map.dart';
import 'widgets/route_map_marker.dart';

String formatRouteDistance(int meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(1)} км'
    : '$meters м';

String formatRouteDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class RouteRecorderScreen extends ConsumerStatefulWidget {
  const RouteRecorderScreen({super.key});

  @override
  ConsumerState<RouteRecorderScreen> createState() =>
      _RouteRecorderScreenState();
}

class _RouteRecorderScreenState extends ConsumerState<RouteRecorderScreen> {
  final _picker = ImagePicker();
  bool _publishing = false;
  bool _confirmingExit = false;
  Duration? _limit;

  Future<void> _addPhoto() async {
    final recorder = ref.read(routeRecorderProvider.notifier);
    if (ref.read(routeRecorderProvider).lastPoint == null) {
      _toast('Ждём первую точку от GPS');
      return;
    }

    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 2048,
    );
    if (shot == null) return;
    recorder.addPhoto(shot.path);
  }

  Future<void> _finish() async {
    ref.read(routeRecorderProvider.notifier).stop();
    final state = ref.read(routeRecorderProvider);

    if (!state.canPublish) {
      _toast('Слишком короткий путь, публиковать нечего');
      return;
    }

    final choice = await showModalBottomSheet<_PublishChoice>(
      context: context, useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PublishSheet(state: state),
    );

    if (choice == null || !mounted) return;
    await _publish(choice);
  }

  Future<void> _publish(_PublishChoice choice) async {
    final title = choice.title;
    setState(() => _publishing = true);
    try {
      final draft = ref
          .read(routeRecorderProvider.notifier)
          .draft(
            title,
            visibility: choice.visibility,
            linkAccess: choice.linkAccess,
          );
      final route = await ref
          .read(routesRepositoryProvider)
          .publishRoute(draft);

      // Маршрут сохранён — теперь он становится видимым в ленте. Если этот шаг
      // упадёт, маршрут не потеряется: он останется у автора в профиле.
      final post = await ref
          .read(feedRepositoryProvider)
          .createPost(
            body: title,
            routeId: route.id,
            settings: PublishSettings(visibility: choice.visibility),
          );

      ref.read(routeRecorderProvider.notifier).reset();
      ref.read(feedProvider.notifier).prepend(post);
      ref.invalidate(myPostsProvider);

      if (!mounted) return;
      context.go('${Routes.routes}/${route.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _toast('Не удалось опубликовать: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(routeRecorderProvider);
    final recorder = ref.read(routeRecorderProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Системный «назад» на Android иначе обходил тот же экран
        // подтверждения, что и кнопка закрытия, и запись оставалась висеть
        // активной за пределами своего экрана. На iOS Cupertino-жест этот
        // колбэк не всегда вызывает — поэтому кнопка закрытия в AppBar
        // остаётся основным путём, а не декорацией.
        _confirmExit(state);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Маршрут'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Закрыть',
            onPressed: () => _confirmExit(state),
          ),
        ),
        body: Stack(
        children: [
          Positioned.fill(
            child: RouteMap(
              path: state.path,
              followLast: state.status == RecordingStatus.recording,
              markers: [
                for (final photo in state.photos)
                  RouteMapMarker(
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                  ),
              ],
            ),
          ),
          if (state.error != null)
            Positioned(
              left: AppSpacing.gutter,
              right: AppSpacing.gutter,
              top: 12,
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: Text(
                  state.error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            ),
          Positioned(
            left: AppSpacing.gutter,
            right: AppSpacing.gutter,
            bottom: 18,
            child: _ControlPanel(
              state: state,
              publishing: _publishing,
              limit: _limit,
              onLimit: (value) => setState(() => _limit = value),
              onStart: () => recorder.start(limit: _limit),
              onPause: recorder.pause,
              onResume: recorder.resume,
              onPhoto: _addPhoto,
              onFinish: _finish,
            ),
          ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit(RouteRecordingState state) async {
    // Публикация уже идёт — не открываем поверх неё диалог про прерывание
    // записи, это про два разных действия одновременно.
    if (_publishing) return;
    // Системный «назад» может дёрнуть колбэк повторно, пока первый диалог
    // ещё не закрыт (двойное нажатие) — не открываем второй поверх первого.
    if (_confirmingExit) return;

    if (!state.isActive) {
      ref.read(routeRecorderProvider.notifier).reset();
      _leave();
      return;
    }

    _confirmingExit = true;
    final _ExitChoice? choice;
    try {
      choice = await showDialog<_ExitChoice>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.ink2,
          title: const Text('Запись маршрута'),
          content: const Text(
            'Можно свернуть: запись продолжится, пока вы пользуетесь другими '
            'вкладками или приложениями. Вернуться — по плашке внизу экрана '
            'или из уведомления.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_ExitChoice.drop),
              child: const Text('Прервать'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_ExitChoice.minimize),
              child: const Text('Свернуть'),
            ),
          ],
        ),
      );
    } finally {
      _confirmingExit = false;
    }

    if (choice == null || !mounted) return;
    if (choice == _ExitChoice.drop) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.ink2,
          title: const Text('Прервать запись?'),
          content: const Text('Записанный путь не сохранится.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Нет'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Прервать'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
      ref.read(routeRecorderProvider.notifier).reset();
    }
    _leave();
  }

  void _leave() {
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go(Routes.feed);
  }
}

enum _ExitChoice { minimize, drop }

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.state,
    required this.publishing,
    required this.limit,
    required this.onLimit,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onPhoto,
    required this.onFinish,
  });

  final RouteRecordingState state;
  final bool publishing;
  final Duration? limit;
  final ValueChanged<Duration?> onLimit;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onPhoto;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(
                label: 'Путь',
                value: formatRouteDistance(state.distanceMeters),
              ),
              _Stat(
                label: 'Время',
                value: formatRouteDuration(state.elapsed),
              ),
              _Stat(label: 'Фото', value: '${state.photos.length}'),
            ],
          ),
          if (state.isActive && state.limit != null) ...[
            const SizedBox(height: 8),
            Text(
              'Остановится сама через '
              '${formatRouteDuration(state.limit! - state.elapsed)}',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
          if (!state.isActive && state.status != RecordingStatus.preparing) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ограничение по времени',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in routeLimitOptions)
                  ChoiceChip(
                    label: Text(routeLimitLabel(option)),
                    selected: option == limit,
                    onSelected: (_) => onLimit(option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (publishing)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryTint,
              ),
            )
          else
            switch (state.status) {
              RecordingStatus.preparing => Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryTint,
                ),
              ),
              RecordingStatus.recording => Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Пауза'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: onPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    tooltip: 'Снять фото на маршруте',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.ink2,
                      foregroundColor: AppColors.primaryTint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onFinish,
                      child: const Text('Финиш'),
                    ),
                  ),
                ],
              ),
              RecordingStatus.paused => Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Продолжить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onFinish,
                      child: const Text('Финиш'),
                    ),
                  ),
                ],
              ),
              _ => FilledButton(
                onPressed: onStart,
                child: const Text('Начать маршрут'),
              ),
            },
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: AppTypography.serif(22)),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(color: AppColors.textDim, fontSize: 11),
      ),
    ],
  );
}

class _PublishChoice {
  const _PublishChoice(this.title, this.visibility, this.linkAccess);

  final String title;
  final PostVisibility visibility;
  final bool linkAccess;
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.state});

  final RouteRecordingState state;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  final _controller = TextEditingController();
  var _visibility = PostVisibility.everyone;
  var _linkAccess = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _visibilityLabels = {
    PostVisibility.everyone: 'Всем',
    PostVisibility.followers: 'Подписчикам',
    PostVisibility.onlyMe: 'Никому',
  };

  String get _visibilityHint => switch (_visibility) {
    PostVisibility.everyone =>
      'Маршрут появится в ленте: его увидят все, включая точки, '
          'где были сделаны фото.',
    PostVisibility.followers =>
      'Маршрут и точки фото увидят только те, кто на тебя подписан.',
    PostVisibility.onlyMe =>
      'В ленте маршрута не будет, увидишь его только ты.',
  };

  @override
  Widget build(BuildContext context) {
    final canPublish = _controller.text.trim().length >= 3;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.gutter,
        top: AppSpacing.gutter,
      ),
      child: SheetCard(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Публикация'),
            const SizedBox(height: 12),
            Text('Как назовём\nмаршрут?', style: AppTypography.serif(28)),
            const SizedBox(height: 14),
            Text(
              '${formatRouteDistance(widget.state.distanceMeters)} · '
              '${formatRouteDuration(widget.state.elapsed)} · '
              '${widget.state.photos.length} фото',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Вечер у моря',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            SegmentedButton<PostVisibility>(
              showSelectedIcon: false,
              segments: [
                for (final entry in _visibilityLabels.entries)
                  ButtonSegment(
                    value: entry.key,
                    label: Text(entry.value, style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
              selected: {_visibility},
              onSelectionChanged: (selected) => setState(() {
                _visibility = selected.first;
                if (_visibility != PostVisibility.onlyMe) _linkAccess = false;
              }),
            ),
            const SizedBox(height: 8),
            Text(_visibilityHint, style: Theme.of(context).textTheme.bodyMedium),
            if (_visibility == PostVisibility.onlyMe)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Открывать по ссылке'),
                subtitle: const Text(
                  'Кто получит ссылку, откроет маршрут. В ленте его всё равно нет.',
                ),
                value: _linkAccess,
                onChanged: (value) => setState(() => _linkAccess = value),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: canPublish
                  ? () => Navigator.of(context).pop(
                      _PublishChoice(_controller.text.trim(), _visibility, _linkAccess),
                    )
                  : null,
              child: const Text('Опубликовать'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
