import '../domain/entities/report_reason.dart';
import '../domain/repositories/report_repository.dart';

class LocalReportRepository implements ReportRepository {
  final _hidden = <String>{};

  @override
  Set<String> get hiddenTargetIds => _hidden;

  @override
  Future<void> submit({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? comment,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _hidden.add(targetId);
  }
}
