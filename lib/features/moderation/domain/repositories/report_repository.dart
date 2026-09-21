import '../entities/report_reason.dart';
// PermissionDeniedException бросают реализации, см. core/permissions.

abstract interface class ReportRepository {
  /// [targetAuthorId] — автор материала: на собственный контент жаловаться
  /// нельзя, репозиторий бросает `PermissionDeniedException`, а сервер
  /// (политика `reports_insert_foreign_only`) не примет такую жалобу и от
  /// клиента, который эту проверку обошёл.
  Future<void> submit({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? comment,
    String? targetAuthorId,
  });

  /// Локальное скрытие: пожаловавшийся не должен видеть контент дальше,
  /// даже пока жалоба в очереди.
  Set<String> get hiddenTargetIds;
}
