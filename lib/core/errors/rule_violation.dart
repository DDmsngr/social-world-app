/// Отказ по правилу предметной области: мест в квесте нет, код прибытия не
/// подошёл, просьба уже закрыта. Серверные функции (миграция 0023) бросают
/// исключение с кодом из [ruleMessages] в тексте; заглушки без сервера
/// бросают этот класс с тем же кодом — экран в обоих случаях получает одно и
/// то же сообщение через `friendlyError`.
class RuleViolation implements Exception {
  const RuleViolation(this.code);

  final String code;

  String get message => ruleMessages[code] ?? 'Действие недоступно';

  @override
  String toString() => 'RuleViolation($code)';
}

/// Коды отказов сервера и их человеческий текст. Ключи — ровно те строки,
/// что стоят в `raise exception` миграции 0023.
const ruleMessages = <String, String>{
  'quest_full': 'Мест больше нет',
  'quest_closed': 'Квест уже закончился',
  'quest_denied': 'Организатор не принял вас в этот квест',
  'quest_is_yours': 'Это ваш квест',
  'quest_bad_code': 'Код не подходит. Уточните его у организатора',
  'quest_not_approved': 'Сначала организатор должен принять заявку',
  'quest_not_participating': 'Вы не участвуете в этом квесте',
  'quest_rules_required': 'Сначала примите правила квестов',
  'quest_rules_outdated': 'Правила обновились — примите новую версию',
  'quest_starts_in_past': 'Время начала уже прошло',
  'quest_bad_point': 'Место встречи указано неверно',
  'quest_not_yours': 'Это не ваш квест',
  'quest_request_not_found': 'Заявка не найдена',
  'quest_not_found': 'Квест не найден',
  'quest_moment_one_photo': 'К квесту можно приложить одну фотографию',
  'quest_moment_not_participant': 'Момент к квесту добавляют только участники',
  'quest_moment_not_moment': 'К квесту привязывается только момент',
  'posts_one_moment_per_quest': 'Вы уже добавили момент к этому квесту',
  'profile_limited': 'Профиль ограничен модерацией',
  'need_bad_point': 'Место указано неверно',
  'need_expired': 'Срок просьбы уже прошёл',
  'need_not_yours': 'Это не ваша просьба',
  'need_not_found': 'Просьба не найдена',
  'need_is_yours': 'Это ваша просьба',
  'need_closed': 'Просьба уже закрыта',
};

/// Код отказа, если он есть в тексте ошибки.
String? ruleCodeIn(Object error) {
  if (error is RuleViolation) return error.code;
  final text = error.toString();
  for (final code in ruleMessages.keys) {
    if (text.contains(code)) return code;
  }
  return null;
}
