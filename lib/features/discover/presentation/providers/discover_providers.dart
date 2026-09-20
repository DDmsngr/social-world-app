import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
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

final discoverDataProvider = FutureProvider<DiscoverSnapshot>((ref) async {
  ref.keepAlive();
  final center = await ref.watch(discoverCenterProvider.future);
  return ref
      .watch(discoverRepositoryProvider)
      .loadNearby(
        centerLatitude: center.latitude,
        centerLongitude: center.longitude,
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

final filteredPlacesProvider = Provider<List<Place>>((ref) {
  ref.keepAlive();
  final query = ref.watch(discoverSearchProvider);
  final categories = ref.watch(categoryFilterProvider);
  final data = ref.watch(discoverDataProvider).value;
  if (data == null) return const [];

  return data.places.where((place) {
    if (categories.isNotEmpty && !categories.contains(place.category)) {
      return false;
    }
    if (query.isEmpty) return true;
    final haystack = [
      place.title,
      place.category ?? '',
      place.description ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }).toList(growable: false);
});
