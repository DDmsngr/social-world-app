import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/sw_widgets.dart';
import '../../core/widgets/user_avatar.dart';
import '../discover/domain/entities/city.dart';

/// Строка рейтинга: место, человек, баллы за период и общий баланс.
class RatingRow {
  const RatingRow({
    required this.place,
    required this.profileId,
    required this.name,
    this.username,
    this.avatarUrl,
    required this.points,
    required this.total,
  });

  factory RatingRow.fromMap(Map<String, dynamic> m, String pointsKey) => RatingRow(
    place: (m['place'] as num?)?.toInt() ?? 0,
    profileId: m['profile_id'] as String,
    name: (m['display_name'] ?? m['name'] ?? m['username'] ?? 'Без имени') as String,
    username: m['username'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    points: (m[pointsKey] as num?)?.toInt() ?? 0,
    total: (m['total_ap'] as num?)?.toInt() ?? 0,
  );

  final int place;
  final String profileId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final int points;
  final int total;
}

/// Шапка экрана — ambassador_overview (миграция 0101).
class AmbassadorOverview {
  const AmbassadorOverview({
    this.seasonEnds,
    this.city,
    this.myPlace,
    this.myPoints,
    required this.prizeMinAp,
    required this.prizesEnabled,
    required this.year,
    required this.leaders,
  });

  factory AmbassadorOverview.fromJson(Map<String, dynamic> j) {
    final season = j['season'] as Map<String, dynamic>?;
    final me = j['me'] as Map<String, dynamic>?;
    return AmbassadorOverview(
      seasonEnds: season == null ? null : DateTime.parse(season['ends_at'] as String).toLocal(),
      city: j['city'] as String?,
      myPlace: (me?['place'] as num?)?.toInt(),
      myPoints: (me?['season_ap'] as num?)?.toInt(),
      prizeMinAp: (j['prize_min_ap'] as num?)?.toInt() ?? 20000,
      prizesEnabled: j['prizes_enabled'] as bool? ?? false,
      year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
      leaders: [
        for (final l in (j['leaders'] as List<dynamic>? ?? const []))
          (
            city: (l as Map)['city'] as String,
            row: RatingRow.fromMap(l.cast<String, dynamic>(), 'season_ap'),
            eligible: l['prize_eligible'] as bool? ?? false,
          ),
      ],
    );
  }

  final DateTime? seasonEnds;
  final String? city;
  final int? myPlace;
  final int? myPoints;
  final int prizeMinAp;
  final bool prizesEnabled;
  final int year;
  final List<({String city, RatingRow row, bool eligible})> leaders;
}

/// Запись Зала славы — ambassador_hall (миграция 0100).
class HallEntry {
  const HallEntry({
    required this.kind,
    this.profileId,
    required this.name,
    this.avatarUrl,
    this.city,
    this.role,
    this.endsAt,
    required this.active,
    this.year,
  });

  factory HallEntry.fromMap(Map<String, dynamic> m) => HallEntry(
    kind: m['kind'] as String,
    profileId: m['profile_id'] as String?,
    name: (m['name'] ?? 'Без имени') as String,
    avatarUrl: m['avatar_url'] as String?,
    city: m['city'] as String?,
    role: m['role'] as String?,
    endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at'] as String).toLocal(),
    active: m['active'] as bool? ?? false,
    year: (m['year'] as num?)?.toInt(),
  );

  final String kind;
  final String? profileId;
  final String name;
  final String? avatarUrl;
  final String? city;
  final String? role;
  final DateTime? endsAt;
  final bool active;
  final int? year;
}

final ambassadorOverviewProvider = FutureProvider.autoDispose<AmbassadorOverview?>((ref) async {
  if (!Env.isConfigured) return null;
  final res = await Supabase.instance.client.rpc('ambassador_overview');
  return res == null ? null : AmbassadorOverview.fromJson((res as Map).cast<String, dynamic>());
});

final ambassadorRatingProvider = FutureProvider.autoDispose.family<List<RatingRow>, String>((ref, city) async {
  if (!Env.isConfigured) return const [];
  final rows = await Supabase.instance.client.rpc('ambassador_rating', params: {'in_city': city}) as List<dynamic>;
  return [for (final r in rows) RatingRow.fromMap((r as Map).cast<String, dynamic>(), 'season_ap')];
});

final ambassadorYearProvider = FutureProvider.autoDispose<List<RatingRow>>((ref) async {
  if (!Env.isConfigured) return const [];
  final rows = await Supabase.instance.client.rpc('ambassador_year_top') as List<dynamic>;
  return [for (final r in rows) RatingRow.fromMap((r as Map).cast<String, dynamic>(), 'year_ap')];
});

final ambassadorHallProvider = FutureProvider.autoDispose<List<HallEntry>>((ref) async {
  if (!Env.isConfigured) return const [];
  final rows = await Supabase.instance.client.rpc('ambassador_hall') as List<dynamic>;
  return [for (final r in rows) HallEntry.fromMap((r as Map).cast<String, dynamic>())];
});

/// Действующий амбассадор или врио — для значка в профиле.
final ambassadorOfProvider = FutureProvider.autoDispose.family<({String city, bool acting})?, String>((ref, id) async {
  if (!Env.isConfigured) return null;
  final rows = await Supabase.instance.client.rpc('ambassador_of', params: {'in_profile': id}) as List<dynamic>;
  if (rows.isEmpty) return null;
  final r = rows.first as Map;
  return (city: r['city'] as String, acting: r['role'] == 'acting');
});

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _ap(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// Амбассадоры городов: рейтинг своего города, лидеры городов, годовой
/// конкурс и Зал славы.
class AmbassadorsScreen extends ConsumerStatefulWidget {
  const AmbassadorsScreen({super.key});

  @override
  ConsumerState<AmbassadorsScreen> createState() => _AmbassadorsScreenState();
}

class _AmbassadorsScreenState extends ConsumerState<AmbassadorsScreen> {
  String? _city;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(ambassadorOverviewProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Амбассадоры'),
          actions: [
            IconButton(
              tooltip: 'Как выбирают амбассадора',
              icon: const Icon(Icons.help_outline),
              onPressed: () => _showHelp(context, overview.value),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Мой город'),
              Tab(text: 'Города'),
              Tab(text: 'Год'),
              Tab(text: 'Зал славы'),
            ],
          ),
        ),
        body: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(friendlyError(e, fallback: 'Не удалось загрузить рейтинг')),
          data: (o) => o == null
              ? const SizedBox.shrink()
              : TabBarView(children: [_cityTab(o), _citiesTab(o), _yearTab(o), const _HallTab()]),
        ),
      ),
    );
  }

  Widget _cityTab(AmbassadorOverview o) {
    final city = _city ?? o.city ?? Cities.fallback.name;
    final rating = ref.watch(ambassadorRatingProvider(city));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(ambassadorRatingProvider(city).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              Expanded(child: Text(city, style: AppTypography.serif(26))),
              PopupMenuButton<String>(
                tooltip: 'Другой город',
                color: AppColors.ink2,
                icon: const Icon(Icons.location_city_outlined),
                onSelected: (c) => setState(() => _city = c),
                itemBuilder: (_) => [for (final c in Cities.all) PopupMenuItem(value: c.name, child: Text(c.name))],
              ),
            ],
          ),
          if (o.seasonEnds != null)
            Text('Сезон идёт до ${_day(o.seasonEnds!)}', style: TextStyle(color: AppColors.textDim)),
          if (city == o.city) ...[
            const SizedBox(height: 12),
            GlassCard(
              child: Text(
                o.myPlace == null
                    ? 'Вас пока нет в рейтинге города: AP за этот сезон ещё не набраны.'
                    : 'Вы на ${o.myPlace} месте, ${_ap(o.myPoints ?? 0)} AP за сезон.',
              ),
            ),
          ] else if (o.city == null) ...[
            const SizedBox(height: 12),
            GlassCard(
              child: Text(
                'В профиле не указан город из списка — рейтинг не знает, за какой город вы участвуете.',
                style: TextStyle(color: AppColors.textDim),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...rating.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [_Message(friendlyError(e, fallback: 'Не удалось загрузить рейтинг'))],
            data: (rows) => rows.isEmpty
                ? [const _Message('В этом сезоне здесь ещё никто не набрал AP.')]
                : [for (final r in rows) _RatingTile(row: r, unit: 'AP')],
          ),
        ],
      ),
    );
  }

  Widget _citiesTab(AmbassadorOverview o) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(ambassadorOverviewProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Лидеры городов', style: AppTypography.serif(26)),
          Text(
            o.prizesEnabled
                ? 'Сезонный приз 30 000 ₽ — лидерам трёх городов с наибольшими AP за сезон, '
                      'если общий баланс от ${_ap(o.prizeMinAp)} AP.'
                : 'Сезонные призы уже разыграны. Лидер города становится кандидатом в амбассадоры.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          if (o.leaders.isEmpty) const _Message('Пока ни в одном городе нет AP за этот сезон.'),
          for (final l in o.leaders)
            _RatingTile(
              row: l.row,
              unit: 'AP',
              leading: l.city,
              badge: o.prizesEnabled && l.eligible ? 'на приз' : null,
            ),
        ],
      ),
    );
  }

  Widget _yearTab(AmbassadorOverview o) {
    final rating = ref.watch(ambassadorYearProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(ambassadorYearProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Конкурс ${o.year} года', style: AppTypography.serif(26)),
          Text(
            'Приз 100 000 ₽ — тому, кто наберёт больше всех AP с 15 декабря ${o.year - 1} '
            'по 15 декабря ${o.year}, во всех городах вместе.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          ...rating.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [_Message(friendlyError(e, fallback: 'Не удалось загрузить рейтинг'))],
            data: (rows) => rows.isEmpty
                ? [const _Message('Пока никто не набрал AP за этот год.')]
                : [for (final r in rows) _RatingTile(row: r, unit: 'AP')],
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context, AmbassadorOverview? o) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.ink2,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Амбассадор города', style: AppTypography.serif(22)),
            const SizedBox(height: 10),
            const Text(
              'В каждом городе один амбассадор. Его выбирают раз в сезон, сезон длится три месяца: '
              'побеждает тот, кто набрал больше всех AP за сезон в своём городе. При равенстве выше '
              'тот, у кого больше общий баланс. Общий баланс после сезона не обнуляется.\n\n'
              'Амбассадор получает значок в профиле, бесплатный Premium на срок полномочий и место '
              'в Зале славы ChaWo — навсегда, даже после окончания срока.\n\n'
              'AP засчитываются за город, указанный в профиле в момент начисления. Premium '
              'на выборы не влияет. Виртуальные авторы и команда ChaWo в конкурсе не участвуют.\n\n'
              'Первых амбассадоров назначает команда ChaWo, дальше — по итогам сезонов. '
              'Итоги проверяются перед присвоением статуса и выплатой призов.',
            ),
            if (o != null && o.seasonEnds != null) ...[
              const SizedBox(height: 10),
              Text('Текущий сезон заканчивается ${_day(o.seasonEnds!)}.', style: TextStyle(color: AppColors.textDim)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HallTab extends ConsumerWidget {
  const _HallTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hall = ref.watch(ambassadorHallProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(ambassadorHallProvider.future),
      child: hall.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(friendlyError(e, fallback: 'Не удалось загрузить Зал славы')),
        data: (entries) {
          final active = entries.where((e) => e.kind == 'ambassador' && e.active).toList();
          final former = entries.where((e) => e.kind == 'ambassador' && !e.active).toList();
          final winners = entries.where((e) => e.kind != 'ambassador').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Зал славы', style: AppTypography.serif(26)),
              if (entries.isEmpty) const _Message('Здесь появятся амбассадоры городов и победители конкурсов.'),
              if (active.isNotEmpty) ...[const _Section('Действующие'), for (final e in active) _HallTile(entry: e)],
              if (winners.isNotEmpty) ...[const _Section('Победители'), for (final e in winners) _HallTile(entry: e)],
              if (former.isNotEmpty) ...[const _Section('Бывшие'), for (final e in former) _HallTile(entry: e)],
            ],
          );
        },
      ),
    );
  }
}

class _HallTile extends StatelessWidget {
  const _HallTile({required this.entry});

  final HallEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final title = switch (e.kind) {
      'year_winner' => 'Победитель конкурса ${e.year} года',
      'season_winner' => 'Призёр сезона${e.city == null ? '' : ' · ${e.city}'}',
      _ => '${e.role == 'acting' ? 'Врио амбассадора' : 'Амбассадор'} · ${e.city ?? ''}',
    };
    final subtitle = e.kind == 'ambassador' && e.endsAt != null
        ? (e.active ? 'до ${_day(e.endsAt!)}' : 'до ${_day(e.endsAt!)} ${e.endsAt!.year}')
        : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(name: e.name, url: e.avatarUrl, radius: 20),
      title: Text(e.name),
      subtitle: Text([title, ?subtitle].join(' · ')),
      onTap: e.profileId == null ? null : () => context.push('${Routes.user}/${e.profileId}'),
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.row, required this.unit, this.leading, this.badge});

  final RatingRow row;
  final String unit;
  final String? leading;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 72,
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                leading == null ? '${row.place}' : '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: row.place == 1 ? AppColors.champagne : AppColors.textDim,
                ),
              ),
            ),
            UserAvatar(name: row.name, url: row.avatarUrl, radius: 20),
          ],
        ),
      ),
      title: Text(leading ?? row.name),
      subtitle: Text([if (leading != null) row.name, ?badge].join(' · ')),
      trailing: Text(
        '${_ap(row.points)} $unit',
        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryTint),
      ),
      onTap: () => context.push('${Routes.user}/${row.profileId}'),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Text(title.toUpperCase(), style: TextStyle(color: AppColors.textFaint, fontSize: 12.5, letterSpacing: 1.2)),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.textDim),
    ),
  );
}

/// Значок под именем в профиле: «Амбассадор · Сочи» или «Врио амбассадора».
class AmbassadorBadge extends ConsumerWidget {
  const AmbassadorBadge({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ambassadorOfProvider(profileId)).value;
    if (status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => context.push(Routes.ambassadors),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.champagne.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.champagne.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, size: 16, color: AppColors.champagne),
              const SizedBox(width: 6),
              Text(
                '${status.acting ? 'Врио амбассадора' : 'Амбассадор'} · ${status.city}',
                style: TextStyle(color: AppColors.champagne, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
