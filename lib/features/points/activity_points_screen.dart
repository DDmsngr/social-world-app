import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../chat/domain/day_label.dart';
import '../referrals/invites.dart';

/// Строка истории: за день по одной причине — одна строка с суммой, иначе
/// десяток лайков засыпал бы экран одинаковыми «+1».
class PointsLine {
  const PointsLine({required this.day, required this.reason, required this.amount, required this.count, this.status});

  final DateTime day;
  final String reason;
  final int amount;
  final int count;

  /// null — уже в балансе; pending / cancelled — ещё не (или уже не) в
  /// балансе: реферальные и начисления за активность до подтверждения.
  final String? status;

  String get title => pointsReasonLabel(reason);
}

/// Подписи причин — те же коды, что пишут в score_events триггеры базы.
String pointsReasonLabel(String reason) {
  if (reason.startsWith('referral_level_')) {
    final level = reason.substring('referral_level_'.length);
    return level == '1' ? 'Приглашённый друг' : 'Приглашение в вашей сети, уровень $level';
  }
  return switch (reason) {
    'post_like' || 'like' => 'Отметки «нравится» на ваших публикациях',
    'post_comment' => 'Комментарии к вашим публикациям',
    'event_visit' => 'Участие в событиях',
    'event_host' => 'Ваши прошедшие события',
    'quest_done' => 'Пройденные квесты',
    'quest_host' => 'Участники прошли ваш квест',
    // Правила до 16.10.2026 — остаются в истории.
    'like_bonus' => 'Бонус за активность',
    'comment_like' => 'Отметки «нравится» на ваших комментариях',
    'event_join' => 'Участники ваших событий',
    'referral_fraud_reversal' => 'Снятие за недействительное приглашение',
    'referral_activation_expired' => 'Приглашённый не выполнил условия',
    _ => 'Прочее',
  };
}

/// Склейка по дню и причине. Порядок — от новых к старым.
List<PointsLine> groupPoints(List<({DateTime at, String reason, int delta, String? status})> raw) {
  final map = <String, PointsLine>{};
  for (final e in raw) {
    final local = e.at.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final key = '${day.toIso8601String()}|${e.reason}|${e.status}';
    final prev = map[key];
    map[key] = PointsLine(
      day: day,
      reason: e.reason,
      amount: (prev?.amount ?? 0) + e.delta,
      count: (prev?.count ?? 0) + 1,
      status: e.status,
    );
  }
  final lines = map.values.where((l) => l.amount != 0 || l.status != null).toList()
    ..sort((a, b) => b.day.compareTo(a.day));
  return lines;
}

class PointsData {
  const PointsData({required this.total, required this.pending, required this.lines});

  final int total;
  final int pending;
  final List<PointsLine> lines;
}

final activityPointsProvider = FutureProvider.autoDispose<PointsData?>((ref) async {
  if (!Env.isConfigured) return null;
  final client = Supabase.instance.client;
  final me = client.auth.currentUser?.id;
  if (me == null) return null;
  final results = await Future.wait([
    client.from('profiles').select('social_score').eq('id', me).single(),
    client.from('score_events').select('reason, delta, created_at').eq('profile_id', me).order('created_at', ascending: false).limit(1000),
    client
        .from('point_transactions')
        .select('code, amount, status, created_at')
        .eq('profile_id', me)
        .inFilter('status', ['pending', 'cancelled'])
        .order('created_at', ascending: false)
        .limit(200),
    // Начисления за активность сутки ждут проверки; отменённые не показываем —
    // это снятые лайки и удалённые комментарии, в балансе их и не было.
    client
        .from('activity_awards')
        .select('code, amount, status, created_at')
        .eq('profile_id', me)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(500),
  ]);
  final profile = results[0] as Map<String, dynamic>;
  final events = results[1] as List<dynamic>;
  final txs = [...results[2] as List<dynamic>, ...results[3] as List<dynamic>];
  final raw = [
    for (final e in events)
      (
        at: DateTime.parse((e as Map)['created_at'] as String),
        reason: e['reason'] as String,
        delta: (e['delta'] as num).toInt(),
        status: null as String?,
      ),
    // Отменённые начисления в баланс не попадали — показываем сами отмены
    // (отрицательные строки), чтобы было видно, куда делось «ожидает».
    for (final t in txs)
      if (!((t as Map)['status'] == 'cancelled' && (t['amount'] as num) > 0))
        (
          at: DateTime.parse(t['created_at'] as String),
          reason: t['code'] as String,
          delta: (t['amount'] as num).toInt(),
          status: t['status'] as String?,
        ),
  ];
  return PointsData(
    total: (profile['social_score'] as num?)?.toInt() ?? 0,
    pending: [
      for (final t in txs)
        if ((t as Map)['status'] == 'pending') (t['amount'] as num).toInt(),
    ].fold(0, (a, b) => a + b),
    lines: groupPoints(raw),
  );
});

/// Правила начисления за активность — из activity_rules и activity_settings,
/// чтобы справка не расходилась с тем, что реально начисляет база.
class ActivityRules {
  const ActivityRules({
    required this.amounts,
    required this.limits,
    required this.dailyCap,
    required this.minGuests,
    required this.perGuest,
    required this.maxGuests,
  });

  final Map<String, int> amounts;
  final Map<String, int?> limits;
  final int dailyCap;
  final int minGuests;
  final int perGuest;
  final int maxGuests;

  /// Значения миграции 0099 — пока правила не загрузились или сервер старый.
  static const fallback = ActivityRules(
    amounts: {'post_like': 1, 'post_comment': 2, 'event_visit': 10, 'event_host': 30, 'quest_done': 20, 'quest_host': 5},
    limits: {'post_like': 50, 'post_comment': 30, 'event_visit': 3, 'event_host': 1, 'quest_done': 3, 'quest_host': 20},
    dailyCap: 300,
    minGuests: 3,
    perGuest: 5,
    maxGuests: 20,
  );

  int amount(String code) => amounts[code] ?? fallback.amounts[code] ?? 0;

  int? limit(String code) => limits.containsKey(code) ? limits[code] : fallback.limits[code];
}

final activityRulesProvider = FutureProvider.autoDispose<ActivityRules>((ref) async {
  if (!Env.isConfigured) return ActivityRules.fallback;
  final client = Supabase.instance.client;
  final results = await Future.wait<dynamic>([
    client.from('activity_rules').select('code, amount, daily_limit'),
    client.from('activity_settings').select().maybeSingle(),
  ]);
  final rules = results[0] as List<dynamic>;
  final s = results[1] as Map<String, dynamic>?;
  const f = ActivityRules.fallback;
  return ActivityRules(
    amounts: {for (final r in rules) (r as Map)['code'] as String: (r['amount'] as num).toInt()},
    limits: {for (final r in rules) (r as Map)['code'] as String: (r['daily_limit'] as num?)?.toInt()},
    dailyCap: (s?['daily_cap'] as num?)?.toInt() ?? f.dailyCap,
    minGuests: (s?['event_host_min_guests'] as num?)?.toInt() ?? f.minGuests,
    perGuest: (s?['event_host_per_guest'] as num?)?.toInt() ?? f.perGuest,
    maxGuests: (s?['event_host_max_guests'] as num?)?.toInt() ?? f.maxGuests,
  );
});

String _perDay(int? n) => switch (n) {
  null => '',
  1 => ' — один раз в день',
  _ => ' — до $n в день',
};

enum _Filter { all, plus, minus }

/// Activity Points — «карма» как на Reddit: сколько и за что получено.
class ActivityPointsScreen extends ConsumerStatefulWidget {
  const ActivityPointsScreen({super.key});

  @override
  ConsumerState<ActivityPointsScreen> createState() => _ActivityPointsScreenState();
}

class _ActivityPointsScreenState extends ConsumerState<ActivityPointsScreen> {
  var _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    ref.read(inviteRepositoryProvider)?.track('activity_points_opened');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(activityPointsProvider);
    final rules = ref.watch(activityRulesProvider).value ?? ActivityRules.fallback;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Points'),
        actions: [
          IconButton(
            tooltip: 'Как получить баллы',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context, rules),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(activityPointsProvider.future),
        child: data.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [Text(friendlyError(error, fallback: 'Не удалось загрузить баллы'))],
          ),
          data: (points) => points == null ? const SizedBox.shrink() : _body(context, points),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PointsData points) {
    final theme = Theme.of(context);
    final lines = points.lines.where((l) => switch (_filter) {
      _Filter.all => true,
      _Filter.plus => l.amount > 0,
      _Filter.minus => l.amount < 0,
    }).toList();
    final now = DateTime.now();
    final children = <Widget>[
      Center(child: Text('${points.total}', style: AppTypography.serif(56))),
      Center(child: Text('баллов сейчас', style: theme.textTheme.bodyMedium)),
      if (points.pending > 0)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+${points.pending} ожидают подтверждения', style: TextStyle(color: AppColors.primaryTint)),
          ),
        ),
      const SizedBox(height: 16),
      SegmentedButton<_Filter>(
        segments: const [
          ButtonSegment(value: _Filter.all, label: Text('Все')),
          ButtonSegment(value: _Filter.plus, label: Text('Начисления')),
          ButtonSegment(value: _Filter.minus, label: Text('Списания')),
        ],
        selected: {_filter},
        onSelectionChanged: (v) => setState(() => _filter = v.first),
      ),
      const SizedBox(height: 8),
    ];
    if (lines.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _filter == _Filter.all
              ? 'Пока пусто. Публикуйте, создавайте события и зовите друзей — баллы появятся здесь.'
              : 'Ничего нет.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ));
    }
    DateTime? day;
    for (final l in lines) {
      if (day != l.day) {
        day = l.day;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(chatDayLabel(l.day, now), style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        ));
      }
      children.add(ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(l.title),
        subtitle: Text([
          if (l.count > 1) '${l.count} раз',
          if (l.status == 'pending') 'ожидает подтверждения',
          if (l.status == 'cancelled') 'отменено',
        ].join(' · ')),
        trailing: Text(
          l.amount > 0 ? '+${l.amount}' : '${l.amount}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: l.amount < 0 ? AppColors.danger : (l.status == 'pending' ? AppColors.textDim : AppColors.primaryTint),
          ),
        ),
      ));
    }
    children.add(const SizedBox(height: 16));
    children.add(FilledButton.icon(
      onPressed: () => context.push(Routes.ambassadors),
      icon: const Icon(Icons.workspace_premium_outlined),
      label: const Text('Рейтинг и амбассадоры'),
    ));
    children.add(const SizedBox(height: 8));
    children.add(OutlinedButton.icon(
      onPressed: () => context.push(Routes.shareApp),
      icon: const Icon(Icons.person_add_alt_1_outlined),
      label: const Text('Пригласить друзей'),
    ));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: children);
  }

  void _showHelp(BuildContext context, ActivityRules r) {
    final points = ref.read(referralOverviewProvider).value?.levelPoints ?? const [100, 50, 25, 15, 10];
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.ink2,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Как получить Activity Points', style: AppTypography.serif(22)),
              const SizedBox(height: 8),
              Text(
                'Баллы — это ваша репутация в ChaWo, как карма на Reddit. Их не тратят: '
                'они показывают, сколько вы дали сообществу.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Text('За активность', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              _Rule(
                points: '+${r.amount('post_like')}',
                text: 'кто-то отметил «нравится» вашу публикацию${_perDay(r.limit('post_like'))}',
              ),
              _Rule(
                points: '+${r.amount('post_comment')}',
                text: 'кто-то прокомментировал вашу публикацию — один раз с человека на публикацию'
                    '${_perDay(r.limit('post_comment'))}',
              ),
              _Rule(
                points: '+${r.amount('event_visit')}',
                text: 'вы записались на событие до его начала, и оно состоялось${_perDay(r.limit('event_visit'))}',
              ),
              _Rule(
                points: '+${r.amount('event_host')} и +${r.perGuest}',
                text: 'ваше событие состоялось, и заранее на него записались не меньше ${r.minGuests} участников; '
                    'плюс +${r.perGuest} за каждого участника, считая до ${r.maxGuests}${_perDay(r.limit('event_host'))}',
              ),
              _Rule(
                points: '+${r.amount('quest_done')}',
                text: 'вы прошли квест и отметились на месте по QR-коду организатора${_perDay(r.limit('quest_done'))}',
              ),
              _Rule(
                points: '+${r.amount('quest_host')}',
                text: 'участник прошёл ваш квест и отметился на месте${_perDay(r.limit('quest_host'))}',
              ),
              const SizedBox(height: 10),
              Text(
                'Баллы за активность приходят через сутки. Если за это время отметку снимут, '
                'комментарий или публикацию удалят, а участие отменят, начисление отменится.\n'
                'Засчитываются действия только людей с подтверждённым номером телефона. '
                'Свои действия и действия виртуальных авторов не считаются.\n'
                'За активность — не больше ${r.dailyCap} баллов в сутки, баллы за приглашения сверх этого.\n'
                'Баллы записываются за город, указанный в вашем профиле в момент начисления: '
                'по ним считается рейтинг города.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Text('За приглашения', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              _Rule(points: '+${points.first}', text: 'друг зарегистрировался по вашему приглашению'),
              if (points.length > 1)
                _Rule(
                  points: '+${points.skip(1).join('/')}',
                  text: 'приглашённые вашими друзьями — уровни 2–${points.length} вашей сети',
                ),
              const SizedBox(height: 22),
              Text('Как работает приглашение', style: AppTypography.serif(20)),
              const SizedBox(height: 10),
              _Step(
                number: '1',
                text: 'У каждого есть своя ссылка, код и QR. Они в «Пригласить друзей» '
                    '(кнопка внизу этого экрана или Настройки → Пригласить в ChaWo). '
                    'Отправьте ссылку другу или покажите QR.',
              ),
              _Step(
                number: '2',
                text: 'Друг ставит приложение и регистрируется. Ссылка сама подставится при '
                    'первом запуске; если не подставилась, друг вводит ваш код вручную '
                    '(Настройки → «Ввести код места»). Сделать это можно в течение недели '
                    'после регистрации.',
              ),
              _Step(
                number: '3',
                text: 'Как только друг зарегистрировался и назвал себя при знакомстве, вам '
                    'приходят баллы: +${points.first} за него, а выше по цепочке приглашений '
                    'получают меньше (${points.skip(1).map((p) => '+$p').join(', ')}). '
                    'Они появляются в течение минуты.',
              ),
              const SizedBox(height: 8),
              Text(
                'Пригласивший у человека один и навсегда. За одного приглашённого можно '
                'получить не больше 200 баллов, в день — не больше 30 приглашений. '
                'Приглашать самого себя, второй аккаунт или одно и то же устройство '
                'бессмысленно: такие приглашения не засчитываются, а баллы снимаются.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: AppColors.primary.withValues(alpha: 0.18),
          child: Text(
            number,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryTint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Rule extends StatelessWidget {
  const _Rule({required this.points, required this.text});

  final String points;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(points, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryTint)),
        ),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
