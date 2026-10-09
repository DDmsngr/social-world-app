import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../chat/domain/day_label.dart';
import '../invites.dart';

/// Ссылка на последнюю сборку — когда персональной ссылки нет (нет сервера).
const appDownloadUrl = 'https://api-socialworld.deepdrift.tech/updates/chawo.apk';

/// «Пригласить в ChaWo»: личная ссылка и QR, статистика сети по уровням,
/// приглашённые и история начислений (ТЗ 8).
class ShareAppScreen extends ConsumerStatefulWidget {
  const ShareAppScreen({super.key});

  @override
  ConsumerState<ShareAppScreen> createState() => _ShareAppScreenState();
}

class _ShareAppScreenState extends ConsumerState<ShareAppScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(inviteRepositoryProvider)?.track('referral_qr_opened');
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(referralOverviewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Пригласить в ChaWo')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(referralOverviewProvider.future),
        child: overview.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Fallback(error: friendlyError(error, fallback: 'Не удалось загрузить приглашения')),
          data: (data) => data == null ? const _Fallback() : _Body(data: data),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});

  final ReferralOverview data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = data.link.toString();
    final repo = ref.read(inviteRepositoryProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Приглашай друзей в ChaWo', style: AppTypography.serif(26)),
        const SizedBox(height: 8),
        Text(
          'Приглашай людей, создавай свою сеть и получай Activity Points.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: QrImageView(
              data: link,
              size: 220,
              backgroundColor: Colors.white,
              semanticsLabel: 'QR-код моего приглашения',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Моя ссылка', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        _Box(child: SelectableText(link, style: TextStyle(fontSize: 13.5, color: AppColors.textDim))),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  repo?.track('referral_link_created', {'via': 'share'});
                  SharePlus.instance.share(
                    ShareParams(text: 'Присоединяйся к ChaWo по моему приглашению: $link'),
                  );
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Поделиться'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  repo?.track('referral_link_created', {'via': 'copy'});
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать'),
              ),
            ),
          ],
        ),
        if (!data.enabled) ...[
          const SizedBox(height: 12),
          Text('Начисления за приглашения сейчас на паузе.', style: TextStyle(color: AppColors.textDim)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _Stat(value: '${data.direct}', label: 'приглашено\nнапрямую')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(value: '${data.network}', label: 'всего\nв сети')),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                value: '${data.earned}',
                label: data.pending > 0 ? 'заработано\n+${data.pending} ждёт' : 'заработано\nбаллов',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Ваша карма: ${data.karma}. Баллы показывают вклад в сообщество — как карма на Reddit.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Text('Уровни сети', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < data.levelPoints.length; i++)
          _LevelRow(level: i + 1, points: data.levelPoints[i], people: data.levels[i + 1] ?? 0),
        const SizedBox(height: 6),
        Text(
          'Баллы приходят, когда приглашённый заполнит профиль и сделает первое действие. '
          'Сначала они ожидают проверки, потом подтверждаются.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        if (data.invitedBy != null)
          Text('Вас пригласил(а) ${data.invitedBy}', style: theme.textTheme.bodyMedium)
        else if (data.canClaim)
          TextButton.icon(
            onPressed: () => _enterCode(context, ref),
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Ввести код пригласившего'),
          ),
        if (data.invites.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Мои приглашения', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final i in data.invites)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i.name),
              subtitle: Text('${chatDayLabel(i.at, DateTime.now())} · ${i.statusLabel}'),
              trailing: i.points > 0 ? Text('+${i.points}', style: TextStyle(color: AppColors.primaryTint)) : null,
            ),
        ],
        if (data.history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('История баллов', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          ..._history(context, data.history),
        ],
      ],
    );
  }

  List<Widget> _history(BuildContext context, List<PointTx> items) {
    final now = DateTime.now();
    final out = <Widget>[];
    String? day;
    for (final t in items) {
      final label = chatDayLabel(t.at, now);
      if (label != day) {
        day = label;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(label, style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        ));
      }
      final hh = t.at.hour.toString().padLeft(2, '0');
      final mm = t.at.minute.toString().padLeft(2, '0');
      out.add(ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(t.title),
        subtitle: Text('$hh:$mm · ${t.statusLabel}${t.reason != null && t.amount < 0 ? '\n${t.reason}' : ''}'),
        trailing: Text(
          t.amount > 0 ? '+${t.amount}' : '${t.amount}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: t.amount < 0 ? AppColors.danger : (t.status == 'pending' ? AppColors.textDim : AppColors.primaryTint),
          ),
        ),
      ));
    }
    return out;
  }

  Future<void> _enterCode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Код пригласившего'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
          decoration: const InputDecoration(hintText: 'ABC234', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Готово')),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.length < 6 || !context.mounted) return;
    final repo = ref.read(inviteRepositoryProvider);
    if (repo == null) return;
    try {
      final inviter = await repo.claim(code, source: 'manual');
      ref.invalidate(referralOverviewProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(inviter == null ? 'Код принят' : 'Вас пригласил(а) $inviter')),
        );
      }
    } catch (error) {
      AppLog.add('Код пригласившего: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: 'Код не принят'))),
        );
      }
    }
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (error != null) ...[
          Text(error!, style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
        ],
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: QrImageView(data: appDownloadUrl, size: 220, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => SharePlus.instance.share(ShareParams(text: 'Заходи в ChaWo: $appDownloadUrl')),
          icon: const Icon(Icons.ios_share),
          label: const Text('Поделиться приложением'),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hair),
    ),
    child: child,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => _Box(
    child: Column(
      children: [
        Text(value, style: AppTypography.serif(24)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
      ],
    ),
  );
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level, required this.points, required this.people});

  final int level;
  final int points;
  final int people;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text('Уровень $level')),
        Expanded(child: Text('+$points за человека', style: TextStyle(color: AppColors.textDim, fontSize: 13))),
        Text('$people чел.'),
      ],
    ),
  );
}
