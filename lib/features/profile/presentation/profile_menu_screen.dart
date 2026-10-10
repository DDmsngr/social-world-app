import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../assistant/assistant.dart';

/// Профиль → ☰. Свои разделы, которые раньше занимали полэкрана профиля:
/// квесты, «Мне надо», сохранённое, импорт и т. п.
class ProfileMenuScreen extends ConsumerWidget {
  const ProfileMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assistant = ref.watch(isAssistantOwnerProvider).value == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои разделы'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: AppSpacing.page(context),
        children: [
          // Квесты — только в своём профиле: чужие активные квесты не
          // показываются никому (п. 43, 44).
          _MenuTile(
            icon: Icons.flag_outlined,
            title: 'Квесты',
            onTap: () => context.push(Routes.myQuests),
          ),
          _MenuTile(
            icon: Icons.volunteer_activism_outlined,
            title: 'Мне надо',
            onTap: () => context.push(Routes.myNeeds),
          ),
          _MenuTile(
            icon: Icons.bookmark_border,
            title: 'Сохранённое',
            onTap: () => context.push(Routes.saved),
          ),
          _MenuTile(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Приглашения',
            onTap: () => context.push(Routes.invites),
          ),
          _MenuTile(
            icon: Icons.move_to_inbox_outlined,
            title: 'Импорт из запрещённограмма',
            onTap: () => context.push(Routes.importData),
          ),
          if (assistant)
            _MenuTile(
              icon: Icons.support_agent,
              title: 'Помощник',
              onTap: () => context.push(Routes.assistant),
            ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryTint),
            const SizedBox(width: 14),
            Expanded(child: Text(title)),
            Icon(Icons.chevron_right, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}
