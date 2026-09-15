import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../data/local_discover_repository.dart';
import '../../data/supabase_discover_repository.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/place.dart';
import '../../domain/repositories/discover_repository.dart';

const discoverCenterLatitude = 43.5789;
const discoverCenterLongitude = 39.7232;

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return LocalDiscoverRepository();
  return SupabaseDiscoverRepository(Supabase.instance.client);
});

final discoverDataProvider = FutureProvider<DiscoverSnapshot>((ref) {
  ref.keepAlive();
  return ref
      .watch(discoverRepositoryProvider)
      .loadNearby(
        centerLatitude: discoverCenterLatitude,
        centerLongitude: discoverCenterLongitude,
      );
});

class DiscoverSearchController extends Notifier<String> {
  @override
  String build() {
    ref.keepAlive();
    return '';
  }

  void update(String value) => state = value.trim().toLowerCase();
}

final discoverSearchProvider =
    NotifierProvider<DiscoverSearchController, String>(
      DiscoverSearchController.new,
    );

final filteredPlacesProvider = Provider<List<Place>>((ref) {
  ref.keepAlive();
  final query = ref.watch(discoverSearchProvider);
  final data = ref.watch(discoverDataProvider).value;
  if (data == null || query.isEmpty) return data?.places ?? const [];

  return data.places
      .where((place) {
        final haystack = [
          place.title,
          place.category ?? '',
          place.description ?? '',
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      })
      .toList(growable: false);
});
