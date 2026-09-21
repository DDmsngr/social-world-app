import '../../../core/permissions/content_permissions.dart';
import '../domain/entities/report_reason.dart';
import '../domain/repositories/report_repository.dart';

class LocalReportRepository implements ReportRepository {
  LocalReportRepository({this.currentUserId});

  final String? Function()? currentUserId;

  final _hidden = <String>{};

  @override
  Set<String> get hiddenTargetIds => _hidden;

  @override
  Future<void> submit({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? comment,
    String? targetAuthorId,
  }) async {
    if (targetAuthorId != null) {
      ContentPermissions(
        viewerId: currentUserId?.call(),
        ownerId: targetAuthorId,
      ).requireForeign();
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _hidden.add(targetId);
  }
}
