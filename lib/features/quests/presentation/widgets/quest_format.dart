import 'package:url_launcher/url_launcher.dart';

import '../../../../core/debug/app_log.dart';
import '../../domain/entities/quest.dart';

const _months = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

/// «сегодня, 19:00» / «3 окт, 19:00».
String formatQuestTime(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final sameDay = local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay
      ? 'сегодня, $hh:$mm'
      : '${local.day} ${_months[local.month - 1]}, $hh:$mm';
}

/// Когда идёт квест — одной строкой для заголовка карточки.
String formatQuestWhen(Quest quest, {DateTime? now}) {
  if (quest.status == QuestStatus.cancelled) return 'Квест отменён';
  if (quest.isTrail || quest.status == QuestStatus.finished) return 'Квест завершён';
  final start = formatQuestTime(quest.startsAt, now: now);
  final end = quest.endsAt;
  if (end == null) {
    return (now ?? DateTime.now()).isBefore(quest.startsAt)
        ? 'Начало: $start'
        : 'Идёт с $start';
  }
  return '$start — ${formatQuestTime(end, now: now)}';
}

/// «Участники: 3/10» или «Участники: 4» — как в карточке ТЗ (п. 22).
String formatOccupancy(Quest quest) => 'Участники: ${quest.occupancy}';

/// Маршрут до точки встречи в Яндекс Картах (п. 22, «Построить маршрут»).
/// Веб-ссылка открывает приложение Карт, если оно стоит, иначе браузер.
Uri questRouteUri(double latitude, double longitude) => Uri.https(
  'yandex.ru',
  '/maps/',
  {'rtext': '~$latitude,$longitude', 'rtt': 'auto'},
);

Future<bool> openQuestRoute(Quest quest) async {
  if (!quest.hasLocation) return false;
  try {
    return await launchUrl(
      questRouteUri(quest.latitude!, quest.longitude!),
      mode: LaunchMode.externalApplication,
    );
  } catch (error) {
    AppLog.add('Маршрут не открылся: $error');
    return false;
  }
}
