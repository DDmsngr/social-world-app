import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/location/distance.dart';
import '../../../events/domain/entities/event.dart';
import '../../../events/presentation/providers/events_providers.dart';
import '../../../feed/domain/entities/post.dart';
import '../../../feed/presentation/providers/feed_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/local_discover_repository.dart';
import '../../data/supabase_discover_repository.dart';
import '../../domain/activity.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/entities/place.dart';
import '../../domain/repositories/discover_repository.dart';
import '../widgets/map_types.dart';

const discoverCenterLatitude = 43.5789;
const discoverCenterLongitude = 39.7232;

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalDiscoverRepository(
      // Без сервера активность считается из того, что лежит в заглушках
      // событий и ленты, — той же формулой, что и на сервере.
      activitySource: () => [
        for (final event in ref.read(eventsProvider).value ?? const <Event>[])
          if (event.hasLocation)
            ActivityObject(
              kind: ActivityKind.event,
              latitude: event.latitude!,
              longitude: event.longitude!,
              participants: event.participantCount,
              startsAt: event.startsAt,
              endsAt: event.endsAt,
            ),
        for (final post in ref.read(feedProvider).value ?? const <Post>[])
          if (post.hasPlaceGeo && post.showGeo)
            ActivityObject(
              kind: ActivityKind.moment,
              latitude: post.placeLatitude!,
              longitude: post.placeLongitude!,
              createdAt: post.createdAt,
            ),
      ],
    );
  }
  return SupabaseDiscoverRepository(Supabase.instance.client);
});

typedef MapCenter = ({double latitude, double longitude});

/// Вокруг какой точки показывать карту и искать, что рядом.
///
/// Берём последнюю известную позицию устройства: она отдаётся мгновенно и не
/// будит GPS, в отличие от getCurrentPosition — карте незачем ждать спутники.
/// Нет разрешения или позиции (первый запуск) — центр Сочи, там идёт пилот.
///
/// Без этого «Рядом» врал: запрос всегда шёл вокруг центра города, и человек
/// в Адлере не видел никого в трёх километрах от себя, хотя своё присутствие
/// публиковал исправно.
final discoverCenterProvider = FutureProvider<MapCenter>((ref) async {
  ref.keepAlive();
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (latitude: last.latitude, longitude: last.longitude);
      }
    }
  } catch (error) {
    // В вебе и в тестах геолокатора нет — это штатный путь, не поломка.
    AppLog.add('Центр карты: позиция устройства недоступна: $error');
  }
  return (latitude: discoverCenterLatitude, longitude: discoverCenterLongitude);
});

/// Точка и радиус сценария «Что есть рядом?». Точку можно взять у устройства
/// или поставить на карте вручную — постоянный доступ к геолокации не нужен.
class NearbyAnchor {
  const NearbyAnchor({
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 1000,
    this.isDevice = false,
  });

  final double latitude;
  final double longitude;
  final int radiusMeters;

  /// true — точка взята с устройства, false — выбрана на карте.
  final bool isDevice;

  NearbyAnchor withRadius(int meters) => NearbyAnchor(
    latitude: latitude,
    longitude: longitude,
    radiusMeters: meters,
    isDevice: isDevice,
  );
}

class NearbyAnchorController extends Notifier<NearbyAnchor?> {
  @override
  NearbyAnchor? build() {
    ref.keepAlive();
    return null;
  }

  void set(NearbyAnchor anchor) => state = anchor;

  void clear() => state = null;
}

final nearbyAnchorProvider =
    NotifierProvider<NearbyAnchorController, NearbyAnchor?>(
      NearbyAnchorController.new,
    );

/// Пока человек выбирает точку на карте, долгий тап по карте ставит якорь.
class PickingAnchorController extends Notifier<bool> {
  @override
  bool build() {
    ref.keepAlive();
    return false;
  }

  void set(bool value) => state = value;
}

final pickingAnchorProvider =
    NotifierProvider<PickingAnchorController, bool>(PickingAnchorController.new);

final discoverDataProvider = FutureProvider<DiscoverSnapshot>((ref) async {
  ref.keepAlive();
  final anchor = ref.watch(nearbyAnchorProvider);
  final center = anchor != null
      ? (latitude: anchor.latitude, longitude: anchor.longitude)
      : await ref.watch(discoverCenterProvider.future);
  return ref
      .watch(discoverRepositoryProvider)
      .loadNearby(
        centerLatitude: center.latitude,
        centerLongitude: center.longitude,
        // Для «Рядом» берём с запасом: расстояние потом уточняется на клиенте.
        radiusMeters: anchor == null ? 3000 : (anchor.radiusMeters * 1.2).round(),
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

/// Пусто = показываем все категории — так фильтр не блокирует список, пока
/// человек ничего не выбрал.
class CategoryFilterController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.keepAlive();
    return const {};
  }

  void toggle(String category) {
    final next = {...state};
    if (!next.remove(category)) next.add(category);
    state = next;
  }

  void clear() => state = const {};
}

final categoryFilterProvider =
    NotifierProvider<CategoryFilterController, Set<String>>(
      CategoryFilterController.new,
    );

/// Какие слои включены. По умолчанию — все: карта открывается «как есть»,
/// а выключение слоя сразу убирает его объекты и их вклад в активность.
class MapLayersController extends Notifier<Set<MapLayer>> {
  static const all = {
    MapLayer.events,
    MapLayer.places,
    MapLayer.people,
    MapLayer.moments,
  };

  @override
  Set<MapLayer> build() {
    ref.keepAlive();
    return all;
  }

  void toggle(MapLayer layer) {
    final next = {...state};
    if (!next.remove(layer)) next.add(layer);
    state = next;
  }

  void reset() => state = all;
}

final mapLayersProvider =
    NotifierProvider<MapLayersController, Set<MapLayer>>(MapLayersController.new);

class ActivityModeController extends Notifier<ActivityMode> {
  @override
  ActivityMode build() {
    ref.keepAlive();
    return ActivityMode.lively;
  }

  void set(ActivityMode mode) => state = mode;
}

final activityModeProvider =
    NotifierProvider<ActivityModeController, ActivityMode>(
      ActivityModeController.new,
    );

/// Куда навести камеру: результат поиска, «Рядом» и т. п. Каждый запрос —
/// новый объект, поэтому повторный выбор того же места тоже сработает.
class MapFocusController extends Notifier<MapFocus?> {
  @override
  MapFocus? build() {
    ref.keepAlive();
    return null;
  }

  void request(double latitude, double longitude, {double zoom = 16}) =>
      state = MapFocus(latitude, longitude, zoom: zoom);
}

final mapFocusProvider =
    NotifierProvider<MapFocusController, MapFocus?>(MapFocusController.new);

/// Возвращает карту в стандартное состояние: все слои, без категорий, без
/// поиска, режим «Сейчас», без якоря «Рядом».
void resetMapFilters(WidgetRef ref) {
  ref.read(mapLayersProvider.notifier).reset();
  ref.read(categoryFilterProvider.notifier).clear();
  ref.read(discoverSearchProvider.notifier).update('');
  ref.read(activityModeProvider.notifier).set(ActivityMode.lively);
  ref.read(nearbyAnchorProvider.notifier).clear();
  ref.read(pickingAnchorProvider.notifier).set(false);
}

/// Что сейчас показывать на карте: единый результат применения слоёв,
/// категорий и поиска ко всем источникам данных.
class MapView {
  const MapView({
    required this.places,
    required this.events,
    required this.people,
    required this.momentCount,
    required this.isFiltered,
  });

  final List<Place> places;
  final List<Event> events;
  final List<NearbyPerson> people;

  /// Свежие моменты с привязкой к месту (в слое активности).
  final int momentCount;

  /// true, если что-то отличается от стандартного состояния карты.
  final bool isFiltered;

  int get shown => places.length + events.length + people.length;
  bool get isEmpty => shown == 0;

  /// Сравнение по содержимому: провайдер пересчитывается от любого чиха
  /// (лайк в ленте, обновление событий), но если на карте показывается то же
  /// самое, экран и камера трогаться не должны.
  @override
  bool operator ==(Object other) =>
      other is MapView &&
      other.isFiltered == isFiltered &&
      other.momentCount == momentCount &&
      listEquals([for (final p in places) p.id], [for (final p in other.places) p.id]) &&
      listEquals([for (final e in events) e.id], [for (final e in other.events) e.id]) &&
      listEquals(
        [for (final p in people) '${p.id}${p.blurredLatitude}${p.blurredLongitude}'],
        [for (final p in other.people) '${p.id}${p.blurredLatitude}${p.blurredLongitude}'],
      );

  @override
  int get hashCode => Object.hash(shown, momentCount, isFiltered);
}

final mapViewProvider = Provider<MapView>((ref) {
  final snapshot = ref.watch(discoverDataProvider).value;
  final layers = ref.watch(mapLayersProvider);
  final categories = ref.watch(categoryFilterProvider);
  final query = ref.watch(discoverSearchProvider);
  final anchor = ref.watch(nearbyAnchorProvider);
  final blocked = ref.watch(blocksProvider).value?.keys.toSet() ?? const <String>{};
  final allEvents = ref.watch(eventsProvider).value ?? const <Event>[];
  final feed = ref.watch(feedProvider).value ?? const <Post>[];

  final filtered =
      layers.length != MapLayersController.all.length ||
      categories.isNotEmpty ||
      query.isNotEmpty ||
      anchor != null;

  if (snapshot == null) {
    return MapView(
      places: const [],
      events: const [],
      people: const [],
      momentCount: 0,
      isFiltered: filtered,
    );
  }

  bool inAnchor(double lat, double lng) =>
      anchor == null ||
      distanceMeters(anchor.latitude, anchor.longitude, lat, lng) <=
          anchor.radiusMeters;

  final categoryByPlaceId = {
    for (final place in snapshot.places) place.id: place.category,
  };

  bool matches(String text) => query.isEmpty || text.toLowerCase().contains(query);

  final places = layers.contains(MapLayer.places)
      ? snapshot.places.where((place) {
          if (categories.isNotEmpty && !categories.contains(place.category)) {
            return false;
          }
          if (!inAnchor(place.latitude, place.longitude)) return false;
          return matches(
            '${place.title} ${place.category ?? ''} ${place.description ?? ''}',
          );
        }).toList(growable: false)
      : const <Place>[];

  final events = layers.contains(MapLayer.events)
      ? allEvents.where((event) {
          if (event.isPast || !event.hasLocation) return false;
          if (blocked.contains(event.authorId)) return false;
          if (categories.isNotEmpty &&
              !categories.contains(categoryByPlaceId[event.placeId])) {
            return false;
          }
          if (!inAnchor(event.latitude!, event.longitude!)) return false;
          return matches('${event.title} ${event.placeTitle ?? ''} ${event.description ?? ''}');
        }).toList(growable: false)
      : const <Event>[];

  final people = layers.contains(MapLayer.people)
      ? snapshot.people.where((person) {
          if (blocked.contains(person.id)) return false;
          if (!inAnchor(person.blurredLatitude, person.blurredLongitude)) {
            return false;
          }
          return matches(person.displayName);
        }).toList(growable: false)
      : const <NearbyPerson>[];

  final moments = layers.contains(MapLayer.moments)
      ? feed
            .where(
              (post) =>
                  post.hasPlaceGeo &&
                  post.showGeo &&
                  DateTime.now().difference(post.createdAt).inHours <=
                      ActivityConfig.defaults.momentMaxAgeH &&
                  (categories.isEmpty ||
                      categories.contains(categoryByPlaceId[post.placeId])),
            )
            .length
      : 0;

  return MapView(
    places: places,
    events: events,
    people: people,
    momentCount: moments,
    isFiltered: filtered,
  );
});

/// Прежний провайдер списка мест — оставлен для совместимости с тестами и
/// экранами, которым нужны только места.
final filteredPlacesProvider = Provider<List<Place>>((ref) {
  ref.keepAlive();
  return ref.watch(mapViewProvider).places;
});

/// Слой активности. Зависит от слоёв, категорий, якоря и режима; пока
/// пересчитывается — отдаёт «загрузку», и карта рисует пустой слой, а не
/// старый поверх нового.
final activityProvider = FutureProvider<List<ActivityCell>>((ref) async {
  final layers = ref.watch(mapLayersProvider);
  final categories = ref.watch(categoryFilterProvider);
  final anchor = ref.watch(nearbyAnchorProvider);

  // «Люди» в оценку активности не входят: это пассивное присутствие, а не
  // события и места; пользователю для этой функции публиковать себя не нужно.
  final activityLayers = layers.difference({MapLayer.people});
  if (activityLayers.isEmpty) return const [];

  final center = anchor != null
      ? (latitude: anchor.latitude, longitude: anchor.longitude)
      : await ref.watch(discoverCenterProvider.future);

  // События и посты влияют на локальный расчёт — следим за ними.
  if (!Env.isConfigured) {
    ref.watch(eventsProvider);
    ref.watch(feedProvider);
  }

  final now = DateTime.now();
  return ref
      .watch(discoverRepositoryProvider)
      .loadActivity(
        ActivityQuery(
          latitude: center.latitude,
          longitude: center.longitude,
          radiusMeters: anchor?.radiusMeters ?? 5000,
          at: DateTime(now.year, now.month, now.day, now.hour, now.minute),
          layers: activityLayers,
          categories: categories,
        ),
      );
});

/// Зоны для рисования: только когда расчёт завершён (не «загрузка») и с
/// учётом режима — ничего лишнего поверх нового результата.
final visibleActivityProvider = Provider<List<ActivityCell>>((ref) {
  final activity = ref.watch(activityProvider);
  final mode = ref.watch(activityModeProvider);
  if (activity.isLoading || activity.hasError) return const [];
  return [
    for (final cell in activity.value ?? const <ActivityCell>[])
      if (cell.intensityFor(mode) > 0.04) cell,
  ];
});

/// Что нашлось по запросу: места, события и люди с карты, плюс люди по имени
/// с сервера. У каждого результата есть либо точка (карта наводится), либо
/// профиль (открывается экран).
enum SearchKind { place, event, nearbyPerson, profile }

class MapSearchResult {
  const MapSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.latitude,
    this.longitude,
    this.avatarUrl,
    this.payload,
  });

  final SearchKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final double? latitude;
  final double? longitude;
  final String? avatarUrl;
  final Object? payload;

  bool get hasPoint => latitude != null && longitude != null;
}

final mapSearchResultsProvider =
    FutureProvider.autoDispose<List<MapSearchResult>>((ref) async {
      final query = ref.watch(discoverSearchProvider);
      if (query.isEmpty) return const [];

      final snapshot = ref.watch(discoverDataProvider).value;
      final blocked = ref.watch(blocksProvider).value?.keys.toSet() ?? const <String>{};
      final events = ref.watch(eventsProvider).value ?? const <Event>[];
      bool matches(String text) => text.toLowerCase().contains(query);

      final results = <MapSearchResult>[];

      for (final place in snapshot?.places ?? const <Place>[]) {
        if (matches('${place.title} ${place.category ?? ''} ${place.description ?? ''}')) {
          results.add(
            MapSearchResult(
              kind: SearchKind.place,
              id: place.id,
              title: place.title,
              subtitle: place.category ?? 'Место',
              latitude: place.latitude,
              longitude: place.longitude,
              payload: place,
            ),
          );
        }
      }

      for (final event in events) {
        if (event.isPast || blocked.contains(event.authorId)) continue;
        if (matches('${event.title} ${event.placeTitle ?? ''} ${event.description ?? ''}')) {
          results.add(
            MapSearchResult(
              kind: SearchKind.event,
              id: event.id,
              title: event.title,
              subtitle: event.placeTitle ?? 'Событие',
              latitude: event.latitude,
              longitude: event.longitude,
              payload: event,
            ),
          );
        }
      }

      final nearbyIds = <String>{};
      for (final person in snapshot?.people ?? const <NearbyPerson>[]) {
        if (blocked.contains(person.id)) continue;
        if (matches(person.displayName)) {
          nearbyIds.add(person.id);
          results.add(
            MapSearchResult(
              kind: SearchKind.nearbyPerson,
              id: person.id,
              title: person.displayName,
              subtitle: 'Рядом',
              latitude: person.blurredLatitude,
              longitude: person.blurredLongitude,
              avatarUrl: person.avatarUrl,
              payload: person,
            ),
          );
        }
      }

      // Люди по имени — на сервере: их положения на карте может и не быть,
      // тогда результат откроет профиль. Сбой поиска не должен ронять
      // остальные результаты.
      if (query.length >= 2) {
        try {
          final hits = await ref.read(profileRepositoryProvider).searchProfiles(query);
          for (final hit in hits) {
            if (nearbyIds.contains(hit.id) || blocked.contains(hit.id)) continue;
            results.add(
              MapSearchResult(
                kind: SearchKind.profile,
                id: hit.id,
                title: hit.displayName,
                subtitle: 'Профиль',
                avatarUrl: hit.avatarUrl,
              ),
            );
          }
        } catch (error) {
          AppLog.add('Поиск людей не удался: $error');
        }
      }

      return results;
    });
