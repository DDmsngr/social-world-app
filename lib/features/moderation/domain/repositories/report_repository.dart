import '../entities/report_reason.dart';

abstract interface class ReportRepository {
  Future<void> submit({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? comment,
  });

  /// Локальное скрытие: пожаловавшийся не должен видеть контент дальше,
  /// даже пока жалоба в очереди.
  Set<String> get hiddenTargetIds;
}
