/// Город, вокруг которого показывается Pulse.
///
/// Pulse обязан работать, даже когда геолокация запрещена или человек далеко
/// от пилотной зоны (ТЗ, п. 10): карта не пустеет и не ломается, а показывает
/// выбранный город. Позиция устройства к выбору города отношения не имеет —
/// она нужна только кнопке «где я» и слою MapKit.
class City {
  const City({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.isPilot = false,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// Пилотная зона: здесь уже есть живые данные. В остальных городах Pulse
  /// пока покажет пустую карту — это честнее, чем прятать их из списка.
  final bool isPilot;

  @override
  bool operator ==(Object other) => other is City && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Список городов первой версии. Порядок — пилот первым, дальше по величине.
/// Мировой масштаб и автоподбор «самой активной области» (ТЗ, п. 6 и 10) сюда
/// добавятся отдельно; список рассчитан на то, чтобы его пополняли, а не
/// переписывали.
abstract final class Cities {
  static const sochi = City(
    id: 'sochi',
    name: 'Сочи',
    latitude: 43.5789,
    longitude: 39.7232,
    isPilot: true,
  );

  static const all = <City>[
    sochi,
    City(id: 'moscow', name: 'Москва', latitude: 55.7558, longitude: 37.6173),
    City(id: 'spb', name: 'Санкт-Петербург', latitude: 59.9391, longitude: 30.3159),
    City(id: 'krasnodar', name: 'Краснодар', latitude: 45.0355, longitude: 38.9753),
    City(id: 'novosibirsk', name: 'Новосибирск', latitude: 55.0084, longitude: 82.9357),
    City(id: 'ekaterinburg', name: 'Екатеринбург', latitude: 56.8389, longitude: 60.6057),
    City(id: 'kazan', name: 'Казань', latitude: 55.7963, longitude: 49.1088),
    City(id: 'nnovgorod', name: 'Нижний Новгород', latitude: 56.3269, longitude: 44.0059),
    City(id: 'rostov', name: 'Ростов-на-Дону', latitude: 47.2357, longitude: 39.7015),
    City(id: 'samara', name: 'Самара', latitude: 53.1959, longitude: 50.1008),
    City(id: 'ufa', name: 'Уфа', latitude: 54.7388, longitude: 55.9721),
    City(id: 'krasnoyarsk', name: 'Красноярск', latitude: 56.0153, longitude: 92.8932),
    City(id: 'voronezh', name: 'Воронеж', latitude: 51.6720, longitude: 39.1843),
    City(id: 'kaliningrad', name: 'Калининград', latitude: 54.7104, longitude: 20.4522),
    City(id: 'vladivostok', name: 'Владивосток', latitude: 43.1155, longitude: 131.8855),
  ];

  /// По умолчанию — пилотная зона: там есть что показать.
  static const fallback = sochi;

  static City parse(String? id) =>
      all.firstWhere((city) => city.id == id, orElse: () => fallback);

  /// Поиск по названию для списка выбора.
  static List<City> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return all;
    return [
      for (final city in all)
        if (city.name.toLowerCase().contains(needle)) city,
    ];
  }

  /// Ближайший город к точке — чем пользоваться, когда позиция устройства
  /// всё-таки есть и человек сам просит «покажи, где я».
  static City nearestTo(double latitude, double longitude) {
    var best = fallback;
    var bestDistance = double.infinity;
    for (final city in all) {
      final dLat = city.latitude - latitude;
      final dLng = (city.longitude - longitude) * 0.6;
      final distance = dLat * dLat + dLng * dLng;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = city;
      }
    }
    return best;
  }
}
