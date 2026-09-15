import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../data/local_report_repository.dart';
import '../../data/supabase_report_repository.dart';
import '../../domain/repositories/report_repository.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  // keepAlive: список скрытого живёт в памяти репозитория, пересоздание
  // вернуло бы в ленту то, на что уже пожаловались.
  ref.keepAlive();
  if (!Env.isConfigured) return LocalReportRepository();
  return SupabaseReportRepository(Supabase.instance.client);
});
