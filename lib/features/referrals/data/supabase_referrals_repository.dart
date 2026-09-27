import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/repositories/referrals_repository.dart';

class SupabaseReferralsRepository implements ReferralsRepository {
  SupabaseReferralsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> recordSignup(String code) =>
      _client.rpc('record_referral_signup', params: {'in_code': code});
}
