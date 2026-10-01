/// Самое раннее и самое позднее время отправки «потом».
const minScheduleLead = Duration(minutes: 1);
const maxScheduleLead = Duration(days: 365);

/// Подходит ли время для отложенной отправки. null — подходит, иначе
/// подсказка для человека.
String? validateSendAt(DateTime at, DateTime now) {
  if (at.isBefore(now.add(minScheduleLead))) {
    return 'Выберите время в будущем — хотя бы через минуту';
  }
  if (at.isAfter(now.add(maxScheduleLead))) {
    return 'Дальше чем на год отложить нельзя';
  }
  return null;
}

const _months = [
  'янв.',
  'фев.',
  'мар.',
  'апр.',
  'мая',
  'июн.',
  'июл.',
  'авг.',
  'сен.',
  'окт.',
  'ноя.',
  'дек.',
];

/// «сегодня в 18:30», «завтра в 09:00», «3 окт. в 09:00».
String formatScheduledAt(DateTime at, DateTime now) {
  final time =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  final label = switch (diff) {
    0 => 'сегодня',
    1 => 'завтра',
    _ =>
      '${at.day} ${_months[at.month - 1]}'
          '${at.year != now.year ? ' ${at.year}' : ''}',
  };
  return '$label в $time';
}
