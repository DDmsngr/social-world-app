import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../data/local_auth_repository.dart';
import '../../data/supabase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// keepAlive обязателен: в Riverpod 3 провайдеры по умолчанию авто-диспозятся,
/// а репозиторий держит сессию в памяти — пересоздание означает разлогин.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return LocalAuthRepository();
  final repo = SupabaseAuthRepository(Supabase.instance.client);
  ref.onDispose(repo.dispose);
  return repo;
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  ref.keepAlive();
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Для виджетов: они подписываются через watch и получают свежее значение.
/// В redirect роутера этим пользоваться нельзя — см. AuthRouterState.
final currentUserProvider = Provider<AppUser?>((ref) {
  ref.keepAlive();
  return ref.watch(authStateProvider).value;
});
