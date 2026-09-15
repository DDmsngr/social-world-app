import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/moderation/data/local_report_repository.dart';
import 'package:social_world/features/moderation/domain/entities/report_reason.dart';

void main() {
  group('LocalReportRepository', () {
    test('после жалобы цель попадает в скрытые', () async {
      final repository = LocalReportRepository();
      expect(repository.hiddenTargetIds, isEmpty);

      await repository.submit(
        target: ReportTarget.post,
        targetId: 'seed-1',
        reason: ReportReason.spam,
      );

      expect(repository.hiddenTargetIds, contains('seed-1'));
    });

    test('у каждой причины есть человеческая подпись', () {
      for (final reason in ReportReason.values) {
        expect(reason.label.trim(), isNotEmpty);
        expect(reason.label, isNot(reason.name));
      }
    });
  });
}
