import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/geo_privacy.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../providers/auth_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  double _radius = GeoPrivacy.defaultRadiusMeters;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
              Text('Как вас\nзвать?', style: AppTypography.serif(36)),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'имя'),
                onChanged: (_) => setState(() {}),
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
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _nameController.text.trim().length < 2 || _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await ref
                            .read(authRepositoryProvider)
                            .completeProfile(displayName: _nameController.text);
                        if (mounted) setState(() => _busy = false);
                      },
                child: const Text('Продолжить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _radiusLabel(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} км вокруг'
      : '${meters.round()} метров вокруг';
}
