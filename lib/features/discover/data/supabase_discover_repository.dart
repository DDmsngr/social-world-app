import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/discover_snapshot.dart';
import '../domain/entities/nearby_person.dart';
import '../domain/entities/place.dart';
import '../domain/repositories/discover_repository.dart';

class SupabaseDiscoverRepository implements DiscoverRepository {
  SupabaseDiscoverRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<DiscoverSnapshot> loadNearby({
    required double centerLatitude,
    required double centerLongitude,
    int radiusMeters = 3000,
  }) async {
    final responses = await Future.wait([
      // Не .from('places').select('...,geo') — PostgREST отдаёт geography
      // сырым hex EWKB, а не GeoJSON/WKT, так что клиенту его не разобрать.
      // RPC возвращает готовые latitude/longitude, как и nearby_profiles.
      _client.rpc(
        'nearby_places',
        params: {
          'in_lat': centerLatitude,
          'in_lng': centerLongitude,
          'in_radius_m': radiusMeters,
          'in_limit': 200,
        },
      ),
      _client.rpc(
        'nearby_profiles',
        params: {
          'in_lat': centerLatitude,
          'in_lng': centerLongitude,
          'in_radius_m': radiusMeters,
          'in_limit': 100,
        },
      ),
    ]);

    final placeRows = responses[0] as List<dynamic>;
    final peopleRows = responses[1] as List<dynamic>;

    return DiscoverSnapshot(
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      places: placeRows
          .map((row) => _placeFromRow(row as Map<String, dynamic>))
          .toList(growable: false),
      // nearby_profiles уже возвращает размытые SQL-функцией координаты.
      people: peopleRows
          .map((row) => _personFromRow(row as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Place _placeFromRow(Map<String, dynamic> row) => Place(
    id: row['id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    category: row['category'] as String?,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
  );

  NearbyPerson _personFromRow(Map<String, dynamic> row) => NearbyPerson(
    id: row['profile_id'] as String,
    displayName: (row['display_name'] as String?) ?? 'Кто-то рядом',
    avatarUrl: row['avatar_url'] as String?,
    blurredLatitude: (row['latitude'] as num).toDouble(),
    blurredLongitude: (row['longitude'] as num).toDouble(),
    blurRadiusMeters: (row['blur_m'] as num).toDouble(),
  );
}
