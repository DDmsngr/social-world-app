import 'nearby_person.dart';
import 'place.dart';

class DiscoverSnapshot {
  const DiscoverSnapshot({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.places,
    required this.people,
  });

  final double centerLatitude;
  final double centerLongitude;
  final List<Place> places;
  final List<NearbyPerson> people;

  int get pulseLevel => people.length >= 8
      ? 3
      : people.length >= 4
      ? 2
      : people.isEmpty
      ? 0
      : 1;
}
