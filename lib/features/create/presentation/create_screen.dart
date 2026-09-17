import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../events/presentation/providers/events_providers.dart';
import '../../feed/presentation/providers/feed_providers.dart';

enum _CreateKind { post, event, route }

String _formatStartsAt(DateTime time) {
  final dd = time.day.toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  final hh = time.hour.toString().padLeft(2, '0');
  final min = time.minute.toString().padLeft(2, '0');
  return '$dd.$mm, $hh:$min';
}

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  var _kind = _CreateKind.post;

  final _bodyController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _placeTitle;
  DateTime? _startsAt;
  bool _busy = false;

  @override
  void dispose() {
    _bodyController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      if (_kind == _CreateKind.post) {
        final post = await ref
            .read(feedRepositoryProvider)
            .createPost(body: _bodyController.text, placeTitle: _placeTitle);

        ref.read(feedProvider.notifier).prepend(post);
        ref.invalidate(myPostsProvider);

        if (!mounted) return;
        _bodyController.clear();
        context.go(Routes.feed);
      } else {
        final event = await ref.read(eventsRepositoryProvider).createEvent(
              title: _titleController.text,
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text,
              startsAt: _startsAt!,
              placeTitle: _placeTitle,
            );

        ref.read(eventsProvider.notifier).append(event);

        if (!mounted) return;
        _titleController.clear();
        _descriptionController.clear();
        context.go(Routes.events);
      }

      setState(() {
        _placeTitle = null;
        _startsAt = null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось опубликовать')),
      );
    }
  }

  Future<void> _pickStartsAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _startsAt == null
          ? const TimeOfDay(hour: 19, minute: 0)
          : TimeOfDay.fromDateTime(_startsAt!),
    );
    if (time == null) return;

    setState(() {
      _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(discoverDataProvider).value?.places ?? const [];
    final canPublish = !_busy &&
        (_kind == _CreateKind.post
            ? _bodyController.text.trim().length >= 3
            : _titleController.text.trim().length >= 3 && _startsAt != null);

    return Scaffold(
      appBar: AppBar(title: const Text('Создать')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          const SectionLabel('Что публикуем'),
          const SizedBox(height: 14),
          SegmentedButton<_CreateKind>(
            segments: const [
              ButtonSegment(value: _CreateKind.post, label: Text('Пост')),
              ButtonSegment(value: _CreateKind.event, label: Text('Событие')),
              ButtonSegment(value: _CreateKind.route, label: Text('Маршрут')),
            ],
            selected: {_kind},
            onSelectionChanged: (selected) =>
                setState(() => _kind = selected.first),
          ),
          const SizedBox(height: 18),
          // Маршрут не пишется формой: его записывает отдельный экран, пока
          // человек идёт по городу.
          if (_kind == _CreateKind.route) ...[
            Text('Пройдите город\nи покажите путь', style: AppTypography.serif(32)),
            const SizedBox(height: 14),
            Text(
              'Приложение запишет ваш путь, пока открыто на экране. По дороге '
              'можно снимать фото — они встанут метками прямо на маршруте. '
              'Опубликуется только то, что вы сами отправите в ленту.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => context.push(Routes.routeRecorder),
              icon: const Icon(Icons.timeline),
              label: const Text('Начать запись'),
            ),
          ],
          if (_kind == _CreateKind.post) ...[
            Text('Что происходит\nв городе?', style: AppTypography.serif(32)),
            const SizedBox(height: 18),
          ] else if (_kind == _CreateKind.event) ...[
            Text('Соберите\nлюдей на событие', style: AppTypography.serif(32)),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Название события'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'О чём событие, что взять с собой',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickStartsAt,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _startsAt == null ? 'Выбрать дату и время' : _formatStartsAt(_startsAt!),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_kind == _CreateKind.post) TextField(
            controller: _bodyController,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Напишите, что увидели или куда зовёте',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_kind != _CreateKind.route) ...[
          const SizedBox(height: 10),
          const SectionLabel('Место'),
          const SizedBox(height: 12),
          Text(
            'Необязательно. Указывается название места, а не ваши координаты.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final place in places)
                ChoiceChip(
                  label: Text(place.title),
                  selected: _placeTitle == place.title,
                  onSelected: (selected) => setState(
                    () => _placeTitle = selected ? place.title : null,
                  ),
                  showCheckmark: false,
                  backgroundColor: AppColors.card,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _placeTitle == place.title
                        ? AppColors.onPrimary
                        : AppColors.textDim,
                  ),
                  side: const BorderSide(color: AppColors.hair),
                ),
            ],
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: canPublish ? _publish : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('Опубликовать'),
          ),
          ],
        ],
      ),
    );
  }
}
