/// На что жалуются. Совпадает с типом `report_target` в базе.
enum ReportTarget { profile, post, place, event }

/// Причины намеренно короткие и на языке пользователя: длинный список
/// с юридическими формулировками люди не читают и жмут первое попавшееся.
enum ReportReason {
  spam('Спам или реклама'),
  harassment('Оскорбления, травля'),
  adult('Материалы 18+'),
  danger('Угроза безопасности'),
  fake('Выдаёт себя за другого'),
  other('Другое');

  const ReportReason(this.label);

  final String label;
}
