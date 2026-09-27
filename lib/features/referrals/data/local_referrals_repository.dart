import '../../../core/debug/app_log.dart';
import '../domain/repositories/referrals_repository.dart';

/// Без сервера коды мест просто не с чем сверять — статистика чисто
/// серверная, копить её в памяти незачем. Запись только в лог, чтобы
/// сценарий не падал в режиме заглушек.
class LocalReferralsRepository implements ReferralsRepository {
  @override
  Future<void> recordSignup(String code) async {
    AppLog.add('Заглушка: код места «$code» на сервере засчитался бы');
  }
}
