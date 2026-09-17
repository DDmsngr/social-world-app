import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local_routes_repository.dart';
import '../../data/supabase_routes_repository.dart';
import '../../domain/entities/city_route.dart';
import '../../domain/repositories/routes_repository.dart';

final routesRepositoryProvider = Provider<RoutesRepository>((ref) {
  // keepAlive: у заглушки маршруты лежат в памяти — пересоздание стёрло бы
  // всё, что человек успел записать за сессию.
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalRoutesRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
      currentUserName: () =>
          ref.read(currentUserProvider)?.displayName ?? 'Вы',
    );
  }
  return SupabaseRoutesRepository(Supabase.instance.client);
});

/// Маршрут целиком — для экрана просмотра и для карточки в ленте.
final routeProvider = FutureProvider.family<CityRoute, String>((ref, id) {
  ref.keepAlive();
  return ref.watch(routesRepositoryProvider).loadRoute(id);
});

/// Маршруты автора — вкладка в профиле.
final authorRoutesProvider =
    FutureProvider.family<List<RouteSummary>, String>((ref, authorId) {
  return ref.watch(routesRepositoryProvider).loadAuthorRoutes(authorId);
});
