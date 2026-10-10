import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../referrals/presentation/widgets/referral_code_sheet.dart';

/// Профиль → ☰ → «Приглашения»: позвать людей и ввести код места. Раньше эти
/// пункты лежали в настройках.
class InvitesScreen extends StatelessWidget {
  const InvitesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryTint),
            const SizedBox(width: 14),
            Expanded(child: Text(label)),
            Icon(Icons.chevron_right, color: AppColors.textFaint),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашения'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: AppSpacing.page(context),
        children: [
          row(Icons.qr_code_2, 'Пригласить в ChaWo', () => context.push(Routes.shareApp)),
          row(Icons.contacts_outlined, 'Пригласить из контактов', () => context.push(Routes.inviteContacts)),
          row(Icons.pin_outlined, 'Ввести код места', () => showReferralCodeSheet(context)),
        ],
      ),
    );
  }
}
