import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.card,
                child: Text(
                  (user?.displayName ?? '?').characters.first.toUpperCase(),
                  style: AppTypography.serif(28, color: AppColors.clay),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Без имени',
                      style: AppTypography.serif(26),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? user?.phone ?? '',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Social Score'),
                Text(
                  '${user?.socialScore ?? 0}',
                  style: AppTypography.serif(24, color: AppColors.sage),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const PhaseList(),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

class PhaseList extends StatelessWidget {
  const PhaseList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SectionLabel('Дальше'),
        SizedBox(height: 12),
        _Row('Публикации и статистика', 'Фаза 1'),
        _Row('Настройки приватности геолокации', 'Фаза 2'),
        _Row('Жалобы и заблокированные', 'Фаза 1'),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.phase);

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            phase,
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
