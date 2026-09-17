import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/media_uploader.dart';
import '../domain/entities/city_route.dart';
import '../domain/repositories/routes_repository.dart';
import 'route_geometry.dart';

class SupabaseRoutesRepository implements RoutesRepository {
  SupabaseRoutesRepository(this._client)
      : _uploader = MediaUploader(_client, bucket: 'route-photos');

  final SupabaseClient _client;
  final MediaUploader _uploader;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Нет активной сессии');
    return id;
  }

  @override
  Future<CityRoute> publishRoute(RouteDraft draft) async {
    if (draft.path.length < 2) {
      throw Exception('В маршруте меньше двух точек — нечего публиковать');
    }

    // Фото уходят первыми: если загрузка упадёт, в базе не останется маршрута
    // с битыми ссылками — просто ничего не создастся.
    final uploaded = <(PendingRoutePhoto, String)>[];
    for (final photo in draft.photos) {
      uploaded.add((photo, await _uploader.upload(photo.localPath)));
    }

    final row = await _client
        .from('routes')
        .insert({
          'author_id': _userId,
          'title': draft.title.trim(),
          'path': RouteGeometry.toEwktLineString(draft.path),
          'distance_m': draft.distanceMeters,
          'duration_s': draft.duration.inSeconds,
          'started_at': draft.startedAt.toUtc().toIso8601String(),
        })
        .select()
        .single();

    final routeId = row['id'] as String;

    if (uploaded.isNotEmpty) {
      await _client.from('route_photos').insert([
        for (final (photo, url) in uploaded)
          {
            'route_id': routeId,
            'photo_url': url,
            'geo': RouteGeometry.toEwktPoint(photo.latitude, photo.longitude),
            'taken_at': photo.takenAt.toUtc().toIso8601String(),
          },
      ]);
    }

    // Пост-обёртку в ленте создаёт вызывающий код через FeedRepository:
    // маршруты и посты — разные репозитории, и лезть отсюда в чужую таблицу
    // значит дублировать логику ленты (place_id, kind, счётчики).
    return loadRoute(routeId);
  }

  @override
  Future<CityRoute> loadRoute(String routeId) async {
    final rows = await _client.rpc(
      'route_detail',
      params: {'in_route': routeId},
    ) as List<dynamic>;

    if (rows.isEmpty) throw Exception('Маршрут не найден');
    final row = rows.first as Map<String, dynamic>;

    return CityRoute(
      id: row['id'] as String,
      authorId: row['author_id'] as String,
      authorName: (row['author_name'] as String?) ?? 'Без имени',
      authorAvatarUrl: row['avatar_url'] as String?,
      title: row['title'] as String,
      path: RouteGeometry.fromGeoJson(row['path']),
      distanceMeters: (row['distance_m'] as num?)?.toInt() ?? 0,
      duration: Duration(seconds: (row['duration_s'] as num?)?.toInt() ?? 0),
      startedAt: DateTime.parse(row['started_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      photos: _photosFrom(row['photos']),
    );
  }

  @override
  Future<void> deleteRoute(String routeId) =>
      _client.from('routes').delete().eq('id', routeId);

  List<RoutePhoto> _photosFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          RoutePhoto(
            id: item['id'] as String,
            photoUrl: item['photo_url'] as String,
            latitude: (item['latitude'] as num).toDouble(),
            longitude: (item['longitude'] as num).toDouble(),
            takenAt: DateTime.parse(item['taken_at'] as String),
            caption: item['caption'] as String?,
          ),
    ];
  }
}
