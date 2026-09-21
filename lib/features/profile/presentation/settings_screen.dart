import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_choice.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../discover/presentation/providers/presence_publisher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      // Низ считается от системной панели (жесты или три кнопки): без этого
      // «Выйти» уезжала под системные клавиши.
      body: ListView(
        padding: AppSpacing.page(context, top: AppSpacing.gutter),
        children: [
          const SectionLabel('Профиль'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            onTap: () => context.push(Routes.editProfile),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, color: AppColors.primaryTint),
                const SizedBox(width: 14),
                const Expanded(child: Text('Редактировать профиль')),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionLabel('Оформление'),
          const SizedBox(height: 12),
          const _ThemePicker(),
          const SizedBox(height: 26),
          const SectionLabel('Приватность геолокации'),
          const SizedBox(height: 12),
          const _GeoPrivacy(),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            onTap: () => context.push(Routes.blocked),
            child: Row(
              children: [
                Icon(Icons.block_outlined, color: AppColors.primaryTint),
                const SizedBox(width: 14),
                const Expanded(child: Text('Заблокированные и скрытые')),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionLabel('Приложение'),
          const SizedBox(height: 12),
          const _UpdateRow(),
          const SizedBox(height: 10),
          const _VersionRow(),
          const SizedBox(height: 26),
          const SectionLabel('Аккаунт'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              // Сначала убираем точку: после signOut сессии уже нет и удалить
              // свою строку в locations будет нечем — человек остался бы
              // висеть на чужих картах до протухания через два часа.
              try {
                await ref.read(discoverRepositoryProvider).clearPresence();
              } catch (_) {
                // Не повод не дать выйти из аккаунта.
              }
              await ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

/// Способы показывать своё присутствие на карте «Рядом». Геолокация самого
/// телефона (чтобы карта нашла вас) и публикация положения другим людям —
/// разные вещи: разрешение ОС ничего не публикует, публикация включается
/// только здесь и всегда размыта до района.
enum _GeoMode {
  hidden('Никому', 'Вас нет на карте у других. Карта для вас работает как обычно.', null),
  approximate('Приблизительно', 'Другие видят пятно района, около 1 км.', 1000),
  district('Район', 'Пятно около 500 м. Так по умолчанию.', 500),
  precise('Точнее', 'Пятно около 200 м — самое точное из возможных.', 200);

  const _GeoMode(this.label, this.hint, this.blurMeters);

  final String label;
  final String hint;

  /// null — присутствие выключено.
  final int? blurMeters;
}

class _GeoPrivacy extends ConsumerStatefulWidget {
  const _GeoPrivacy();

  @override
  ConsumerState<_GeoPrivacy> createState() => _GeoPrivacyState();
}

class _GeoPrivacyState extends ConsumerState<_GeoPrivacy> {
  _GeoMode? _pending;
  var _saving = false;

  _GeoMode _current() {
    if (!ref.read(presenceEnabledProvider)) return _GeoMode.hidden;
    final blur = ref.read(currentUserProvider)?.locationBlurM ?? 500;
    if (blur <= 300) return _GeoMode.precise;
    if (blur <= 700) return _GeoMode.district;
    return _GeoMode.approximate;
  }

  Future<void> _choose(_GeoMode mode) async {
    if (_saving) return;
    setState(() {
      _pending = mode;
      _saving = true;
    });
    try {
      final blur = mode.blurMeters;
      if (blur == null) {
        // Выключение убирает точку с карты сразу, не дожидаясь протухания.
        await ref.read(presenceEnabledProvider.notifier).set(false);
      } else {
        await ref.read(authRepositoryProvider).updateLocationBlur(blur);
        await ref.read(presenceEnabledProvider.notifier).set(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось сохранить'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pending = null;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Подписка на оба источника: режим пересчитывается после сохранения.
    ref.watch(presenceEnabledProvider);
    ref.watch(currentUserProvider);
    final current = _pending ?? _current();

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
            child: Text(
              'Кому видно, что вы рядом. Точные координаты не покидают телефон: '
              'публикуется только размытая точка, пока приложение открыто. '
              'Маршрут прогулки — отдельно: если вы публикуете его сами, путь '
              'виден точно.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          for (final mode in _GeoMode.values)
            Semantics(
              button: true,
              selected: mode == current,
              inMutuallyExclusiveGroup: true,
              child: InkWell(
                onTap: () => _choose(mode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mode.label),
                            Text(
                              mode.hint,
                              style: TextStyle(fontSize: 12, color: AppColors.textDim),
                            ),
                          ],
                        ),
                      ),
                      if (mode == current)
                        _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.check, color: AppColors.primaryTint),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: Text(
              'Место в конкретном посте задаётся отдельно — галочкой '
              '«Показывать место публикации» при создании.',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeChoiceProvider);

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final choice in ThemeChoice.values)
            Semantics(
              button: true,
              selected: choice == current,
              inMutuallyExclusiveGroup: true,
              child: InkWell(
                onTap: () =>
                    ref.read(themeChoiceProvider.notifier).choose(choice),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(choice.label),
                            if (choice.hint != null)
                              Text(
                                choice.hint!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textDim,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (choice == current)
                        Icon(Icons.check, color: AppColors.primaryTint),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return GlassCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Версия'),
              Text(
                info == null
                    ? '…'
                    : '${info.version} (${info.buildNumber})',
                style: TextStyle(color: AppColors.textDim),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final label = switch (state.stage) {
      UpdateStage.checking => 'Проверяем…',
      UpdateStage.available => 'Доступно обновление',
      UpdateStage.downloading => 'Скачивается…',
      UpdateStage.readyToInstall => 'Готово к установке',
      UpdateStage.failed => 'Не удалось проверить',
      _ => 'Вы используете последнюю версию',
    };

    return GlassCard(
      onTap: state.stage == UpdateStage.downloading
          ? null
          : () => ref
                .read(updateControllerProvider.notifier)
                .check(silent: false),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Обновления'),
          Text(label, style: TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }
}
