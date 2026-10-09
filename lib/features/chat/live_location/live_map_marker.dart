/// Человек на карте трансляции.
class LiveMapMarker {
  const LiveMapMarker({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.avatarUrl,
    this.me = false,
  });

  final double latitude;
  final double longitude;
  final String label;
  final String? avatarUrl;
  final bool me;
}
