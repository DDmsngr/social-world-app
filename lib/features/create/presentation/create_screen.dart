import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../feed/presentation/providers/feed_providers.dart';

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  final _bodyController = TextEditingController();
  String? _placeTitle;
  bool _busy = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      final post = await ref
          .read(feedRepositoryProvider)
          .createPost(body: _bodyController.text, placeTitle: _placeTitle);

      ref.read(feedProvider.notifier).prepend(post);
      ref.invalidate(myPostsProvider);

      if (!mounted) return;
      _bodyController.clear();
      setState(() {
        _placeTitle = null;
        _busy = false;
      });
      context.go(Routes.feed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось опубликовать')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(discoverDataProvider).value?.places ?? const [];
    final canPublish = _bodyController.text.trim().length >= 3 && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('Создать')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          const SectionLabel('Публикация'),
          const SizedBox(height: 14),
          Text('Что происходит\nв городе?', style: AppTypography.serif(32)),
          const SizedBox(height: 18),
          TextField(
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
      ),
    );
  }
}
