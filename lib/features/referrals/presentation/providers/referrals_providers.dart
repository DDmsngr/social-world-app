import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../data/local_referrals_repository.dart';
import '../../data/supabase_referrals_repository.dart';
import '../../domain/repositories/referrals_repository.dart';

final referralsRepositoryProvider = Provider<ReferralsRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return LocalReferralsRepository();
  return SupabaseReferralsRepository(Supabase.instance.client);
});
