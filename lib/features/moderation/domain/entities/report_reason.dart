/// На что жалуются. Совпадает с типом `report_target` в базе (quest и need —
/// с миграции 0023).
enum ReportTarget { profile, post, place, event, quest, need }

/// Причины намеренно короткие и на языке пользователя: длинный список
/// с юридическими формулировками люди не читают и жмут первое попавшееся.
enum ReportReason {
  spam('Спам или реклама'),
  harassment('Оскорбления, травля'),
  adult('Материалы 18+'),
  danger('Угроза безопасности'),
  fake('Выдаёт себя за другого'),
  rules('Нарушение правил'),
  suspicious('Подозрительный контент'),
  wrongInfo('Неверная информация'),
  dangerousActivity('Опасная активность'),
  other('Другое');

  const ReportReason(this.label);

  final String label;

  /// Какие причины предлагать для объекта. У квеста — список из ТЗ (п. 51):
  /// там важнее «опасная активность», чем «выдаёт себя за другого».
  static List<ReportReason> forTarget(ReportTarget target) => switch (target) {
    ReportTarget.quest => const [rules, suspicious, wrongInfo, dangerousActivity, other],
    ReportTarget.need => const [spam, rules, suspicious, dangerousActivity, other],
    _ => const [spam, harassment, adult, danger, fake, other],
  };
}
