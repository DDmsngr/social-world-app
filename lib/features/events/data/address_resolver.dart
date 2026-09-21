import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../discover/domain/entities/place.dart';
import '../domain/entities/event_route.dart';

/// Превращает введённый адрес в координаты. За интерфейсом, чтобы заменить
/// поставщика (например, на HTTP-геокодер Яндекса, когда у проекта будет
/// его ключ) без правок экрана.
abstract interface class Geocoder {
  Future<EventRoutePoint?> geocode(String query);
}

/// Публичный Nominatim (OpenStreetMap). Годится для MVP: один запрос за
/// нажатие «+» укладывается в их политику (не чаще раза в секунду, свой
/// User-Agent). На больших объёмах нужен свой геокодер.
class NominatimGeocoder implements Geocoder {
  NominatimGeocoder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Рамка вокруг Сочи и побережья: результаты внутри неё выигрывают у
  /// одноимённых улиц в других городах.
  static const _viewbox = '39.2,44.0,40.6,43.3';

  @override
  Future<EventRoutePoint?> geocode(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '1',
      'accept-language': 'ru',
      'countrycodes': 'ru',
      'viewbox': _viewbox,
    });

    final response = await _client
        .get(uri, headers: {'User-Agent': 'SocialWorld/1.0 (ru.socialworld.app)'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('Геокодер ответил ${response.statusCode}');
    }

    final rows = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    if (rows.isEmpty) return null;

    final row = rows.first as Map<String, dynamic>;
    final lat = double.tryParse('${row['lat']}');
    final lng = double.tryParse('${row['lon']}');
    if (lat == null || lng == null) return null;
    return EventRoutePoint(latitude: lat, longitude: lng, title: query.trim());
  }
}

/// Сначала ищем среди известных мест приложения («Морской порт», «Дендрарий»):
/// это быстрее, точнее и не уходит во внешний сервис. Не нашли — геокодер.
class AddressResolver {
  AddressResolver({required this.places, required this.geocoder});

  final List<Place> places;
  final Geocoder geocoder;

  Future<EventRoutePoint?> resolve(String input) async {
    final query = input.trim();
    if (query.length < 2) return null;

    final known = matchPlace(query);
    if (known != null) {
      return EventRoutePoint(
        latitude: known.latitude,
        longitude: known.longitude,
        title: known.title,
      );
    }
    return geocoder.geocode(query);
  }

  /// Точное совпадение названия важнее вхождения; при нескольких вхождениях
  /// берётся самое короткое название — оно ближе к тому, что напечатал человек.
  Place? matchPlace(String query) {
    final needle = query.trim().toLowerCase();
    Place? best;
    for (final place in places) {
      final title = place.title.toLowerCase();
      if (title == needle) return place;
      if (title.contains(needle) &&
          (best == null || place.title.length < best.title.length)) {
        best = place;
      }
    }
    return best;
  }

  /// Подсказки по мере ввода — только из своих мест, без сетевых запросов.
  List<Place> suggestions(String query, {int limit = 4}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return places
        .where((place) => place.title.toLowerCase().contains(needle))
        .take(limit)
        .toList(growable: false);
  }
}
