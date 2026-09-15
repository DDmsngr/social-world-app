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
      _client.from('places').select('id,title,description,category,geo'),
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

  Place _placeFromRow(Map<String, dynamic> row) {
    final point = _readPoint(row['geo']);
    return Place(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String?,
      latitude: point.$1,
      longitude: point.$2,
    );
  }

  NearbyPerson _personFromRow(Map<String, dynamic> row) => NearbyPerson(
    id: row['profile_id'] as String,
    displayName: (row['display_name'] as String?) ?? 'Кто-то рядом',
    avatarUrl: row['avatar_url'] as String?,
    blurredLatitude: (row['latitude'] as num).toDouble(),
    blurredLongitude: (row['longitude'] as num).toDouble(),
    blurRadiusMeters: (row['blur_m'] as num).toDouble(),
  );

  (double, double) _readPoint(dynamic geo) {
    if (geo is Map<String, dynamic>) {
      final coordinates = geo['coordinates'];
      if (coordinates is List && coordinates.length >= 2) {
        return (
          (coordinates[1] as num).toDouble(),
          (coordinates[0] as num).toDouble(),
        );
      }
    }

    final match = RegExp(
      r'^POINT\s*\(([-+\d.eE]+)\s+([-+\d.eE]+)\)$',
    ).firstMatch(geo?.toString() ?? '');
    if (match != null) {
      return (double.parse(match.group(2)!), double.parse(match.group(1)!));
    }
    throw const FormatException('Не удалось прочитать координаты места');
  }
}
