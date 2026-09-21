import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/permissions/content_permissions.dart';
import '../domain/entities/report_reason.dart';
import '../domain/repositories/report_repository.dart';

class SupabaseReportRepository implements ReportRepository {
  SupabaseReportRepository(this._client);

  final SupabaseClient _client;
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
    final reporterId = _client.auth.currentUser?.id;
    if (reporterId == null) throw const AuthException('Нет активной сессии');
    if (targetAuthorId != null) {
      ContentPermissions(
        viewerId: reporterId,
        ownerId: targetAuthorId,
      ).requireForeign();
    }

    await _client.from('reports').insert({
      'reporter_id': reporterId,
      'target': target.name,
      'target_id': targetId,
      'reason': reason.name,
      'comment': comment?.trim(),
    });

    // Прячем локально сразу: city_feed отфильтрует это только при следующей
    // загрузке, а пользователь ждёт реакции сейчас.
    _hidden.add(targetId);
  }
}
