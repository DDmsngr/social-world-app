const _monthsGenitive = [
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

/// Один и тот же календарный день (по местному времени).
bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Подпись дня над сообщениями, как в Telegram: «Сегодня», «Вчера»,
/// «7 октября», в прошлые годы — «7 октября 2025».
String chatDayLabel(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Вчера';
  final base = '${local.day} ${_monthsGenitive[local.month - 1]}';
  return local.year == now.year ? base : '$base ${local.year}';
}
