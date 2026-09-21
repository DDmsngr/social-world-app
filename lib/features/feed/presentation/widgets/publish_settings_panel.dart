import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/post.dart';
import '../../domain/entities/publish_settings.dart';
import '../providers/publish_settings_provider.dart';

/// Поля настроек: «кому показывать» и «показывать место». Чистый виджет без
/// провайдеров — им пользуются и форма создания, и лист правки готового поста.
class PublishSettingsFields extends StatelessWidget {
  const PublishSettingsFields({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final PublishSettings settings;
  final ValueChanged<PublishSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Кому показывать', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SegmentedButton<PostVisibility>(
          showSelectedIcon: false,
          segments: [
            for (final visibility in PostVisibility.values)
              ButtonSegment(
                value: visibility,
                label: Text(visibility.label, style: const TextStyle(fontSize: 12.5)),
              ),
          ],
          selected: {settings.visibility},
          onSelectionChanged: (selected) =>
              onChanged(settings.copyWith(visibility: selected.first)),
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          value: settings.showGeo,
          onChanged: (value) =>
              onChanged(settings.copyWith(showGeo: value ?? true)),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
          checkColor: AppColors.onPrimary,
          title: const Text('Показывать место публикации'),
          subtitle: Text(
            settings.showGeo
                ? 'Название места видно в посте и учитывается на карте'
                : 'Место не покажем и на карте пост не появится',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// Настройки в форме создания: строка-сводка, чипы-пресеты одним нажатием и
/// раскрывающиеся чекбоксы. Свёрнуто по умолчанию, чтобы не перегружать экран.
class PublishSettingsPanel extends ConsumerStatefulWidget {
  const PublishSettingsPanel({super.key});

  @override
  ConsumerState<PublishSettingsPanel> createState() =>
      _PublishSettingsPanelState();
}

class _PublishSettingsPanelState extends ConsumerState<PublishSettingsPanel> {
  var _expanded = false;

  Future<void> _savePreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название настройки'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Например, «Друзья»'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await ref.read(publishSettingsProvider.notifier).savePreset(name);
  }

  Future<void> _deletePreset(PublishPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить «${preset.name}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(publishSettingsProvider.notifier).deletePreset(preset.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publishSettingsProvider);
    final controller = ref.read(publishSettingsProvider.notifier);
    final active = state.activePreset;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Настройки публикации: ${state.current.summary}',
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18, color: AppColors.primaryTint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Настройки публикации',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            state.current.summary,
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in state.presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () => _deletePreset(preset),
                      child: ChoiceChip(
                        label: Text(preset.name),
                        tooltip: 'Зажмите, чтобы удалить',
                        selected: active?.id == preset.id,
                        onSelected: (_) => controller.applyPreset(preset),
                        showCheckmark: false,
                        backgroundColor: AppColors.ink2,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: active?.id == preset.id
                              ? AppColors.onPrimary
                              : AppColors.textDim,
                        ),
                        side: BorderSide(color: AppColors.hair),
                      ),
                    ),
                  ),
                // «+» только когда текущий набор ещё не сохранён: иначе кнопка
                // предлагала бы создать дубль того, что уже есть в чипах.
                if (active == null)
                  ActionChip(
                    avatar: Icon(Icons.add, size: 16, color: AppColors.primaryTint),
                    label: Text(
                      state.presets.isEmpty ? 'Сохранить как настройку' : 'Сохранить',
                    ),
                    onPressed: _savePreset,
                    backgroundColor: AppColors.ink2,
                    side: BorderSide(color: AppColors.hair),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: PublishSettingsFields(
                      settings: state.current,
                      onChanged: controller.update,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Лист настроек для уже опубликованного поста. Возвращает выбранное или null.
class PublishSettingsSheet extends StatefulWidget {
  const PublishSettingsSheet({super.key, required this.initial});

  final PublishSettings initial;

  @override
  State<PublishSettingsSheet> createState() => _PublishSettingsSheetState();
}

class _PublishSettingsSheetState extends State<PublishSettingsSheet> {
  late PublishSettings _settings = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Настройки публикации'),
            const SizedBox(height: 14),
            PublishSettingsFields(
              settings: _settings,
              onChanged: (next) => setState(() => _settings = next),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_settings),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
