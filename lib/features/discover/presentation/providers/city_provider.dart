import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/city.dart';

const _prefsKey = 'pulse_city';

/// Выбор, прочитанный в main() до первого кадра: иначе Pulse на секунду
/// открывается на пилотном городе и только потом переезжает на выбранный.
final initialCityProvider = Provider<City>((_) => Cities.fallback);

Future<City> loadCity() async {
  final prefs = await SharedPreferences.getInstance();
  return Cities.parse(prefs.getString(_prefsKey));
}

class CityController extends Notifier<City> {
  @override
  City build() {
    ref.keepAlive();
    return ref.read(initialCityProvider);
  }

  Future<void> choose(City city) async {
    if (city == state) return;
    state = city;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, city.id);
  }
}

/// Город, вокруг которого работает Pulse. От него зависят центр карты,
/// «что рядом» и слой активности.
final cityProvider = NotifierProvider<CityController, City>(CityController.new);
