import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../data/local_auth_repository.dart';
import '../../data/supabase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!Env.isConfigured) return LocalAuthRepository();
  return SupabaseAuthRepository(Supabase.instance.client);
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Синхронный срез для редиректов роутера — стрим может ещё грузиться,
/// а решение о маршруте нужно прямо сейчас.
final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authStateProvider).value ??
      ref.watch(authRepositoryProvider).currentUser;
});
