import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/location/geo_privacy.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../profile/presentation/avatar_crop_screen.dart';
import '../../../discover/domain/entities/city.dart';
import '../../../discover/presentation/providers/city_provider.dart';
import '../../../discover/presentation/widgets/city_picker.dart';
import '../../../shell/presentation/app_tour.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';

/// Знакомство после первого входа: имя, город, по желанию @ник. Город не
/// подставляется сам — раньше всем ставился Сочи, и человек открывал карту
/// чужого города. После знакомства показывается проводник по вкладкам.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _nickController;
  City? _city;

  /// Фото с телефона, выбранное вместо картинки от VK/Яндекса.
  String? _avatarPath;
  double _radius = GeoPrivacy.defaultRadiusMeters;
  bool _busy = false;
  String? _error;
  String? _nickError;

  @override
  void initState() {
    super.initState();
    final me = ref.read(currentUserProvider);
    // Вход через VK/Яндекс уже знает имя — подставляем, человек поправит.
    _nameController = TextEditingController(text: me?.displayName ?? '');
    _nickController = TextEditingController(text: me?.username ?? '');
    _city = Cities.byName(me?.city);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nickController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameController.text.trim().length >= 2 &&
      _city != null &&
      Username.validate(_nickController.text) == null;

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    // Сразу настройка кадра: видно, как фото ляжет в кружок.
    final framed = await openAvatarCrop(context, source: file.path);
    if (!mounted) return;
    setState(() => _avatarPath = framed ?? file.path);
  }

  Future<void> _pickCity() async {
    final city = await chooseCity(context, selected: _city);
    if (city != null && mounted) setState(() => _city = city);
  }

  Future<void> _submit() async {
    final city = _city;
    if (city == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _nickError = null;
    });
    try {
      // Сначала карта и проводник: completeProfile переключит роутер на
      // вкладки, и они должны открыться уже на выбранном городе.
      await ref.read(cityProvider.notifier).choose(city);
      await AppTour.markPending();
      // Своё фото — до завершения знакомства: completeProfile переключит
      // роутер на вкладки, и аватар должен уже стоять.
      final avatar = _avatarPath;
      if (avatar != null) {
        await ref.read(authRepositoryProvider).updateProfile(avatarLocalPath: avatar);
      }
      await ref.read(authRepositoryProvider).completeProfile(
            displayName: _nameController.text,
            city: city.name,
            username: _nickController.text,
          );
    } on UsernameTakenException catch (e) {
      if (mounted) setState(() => _nickError = e.toString());
    } catch (e) {
      AppLog.add('Onboarding: completeProfile упал — $e');
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const SectionLabel('Знакомство'),
              const SizedBox(height: 14),
              Text('Представьтесь,\nпожалуйста', style: AppTypography.serif(36)),
              const SizedBox(height: 20),
              _avatarBlock(),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Имя'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nickController,
                autocorrect: false,
                maxLength: 21,
                decoration: InputDecoration(
                  labelText: 'Ник (необязательно)',
                  prefixText: '@',
                  helperText: 'По нику вас найдут, не зная номера телефона',
                  errorText: _nickError ?? Username.validate(_nickController.text),
                ),
                onChanged: (_) => setState(() => _nickError = null),
              ),
              const SizedBox(height: 20),
              const SectionLabel('Ваш город'),
              const SizedBox(height: 10),
              Text(
                'Лента и карта покажут жизнь этого города. Поменять можно '
                'в любой момент на карте.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickCity,
                icon: const Icon(Icons.location_city_outlined),
                label: Text(_city?.name ?? 'Выбрать город'),
              ),
              const SizedBox(height: 32),
              const SectionLabel('Геопозиция'),
              const SizedBox(height: 14),
              Text('Насколько точно\nвас видно', style: AppTypography.serif(28)),
              const SizedBox(height: 12),
              Text(
                'Точные координаты остаются на телефоне. Другие видят только '
                'район — точку в центре области выбранного размера. Поменять '
                'можно в любой момент в настройках.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _radiusLabel(_radius),
                      style: AppTypography.serif(22, color: AppColors.primaryTint),
                    ),
                    Slider(
                      value: GeoPrivacy.radiusOptions.indexOf(_radius).toDouble(),
                      min: 0,
                      max: (GeoPrivacy.radiusOptions.length - 1).toDouble(),
                      divisions: GeoPrivacy.radiusOptions.length - 1,
                      activeColor: AppColors.primaryTint,
                      inactiveColor: AppColors.hairStrong,
                      onChanged: (value) => setState(
                        () => _radius = GeoPrivacy.radiusOptions[value.round()],
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: !_valid || _busy ? null : _submit,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text('Продолжить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Фото профиля: если вход принёс картинку от VK/Яндекса, она маленькая и
  /// часто не та, поэтому сразу предлагаем загрузить своё или оставить эту.
  Widget _avatarBlock() {
    final me = ref.watch(currentUserProvider);
    final providerUrl = me?.avatarUrl;
    final own = _avatarPath;
    return Row(
      children: [
        if (own != null)
          CircleAvatar(radius: 40, backgroundImage: FileImage(File(own)))
        else
          UserAvatar(
            name: _nameController.text.isEmpty ? (me?.displayName ?? '?') : _nameController.text,
            url: providerUrl,
            userId: me?.id,
            radius: 40,
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                own != null
                    ? 'Ваше фото'
                    : providerUrl != null
                    ? 'Фото с площадки входа'
                    : 'Фото профиля',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                own == null && providerUrl != null
                    ? 'Оно небольшое. Можно оставить или загрузить своё.'
                    : 'Можно поменять позже в профиле.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    style: AppButtons.compact,
                    onPressed: _busy ? null : _pickAvatar,
                    child: Text(own == null ? 'Загрузить своё' : 'Другое фото'),
                  ),
                  if (own != null && providerUrl != null)
                    TextButton(
                      style: AppButtons.compact,
                      onPressed: _busy ? null : () => setState(() => _avatarPath = null),
                      child: const Text('Оставить прежнее'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _radiusLabel(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} км вокруг'
      : '${meters.round()} метров вокруг';
}
