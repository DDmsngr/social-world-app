class Place {
  const Place({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    this.description,
    this.category,
  });

  final String id;
  final String title;
  final String? description;
  final String? category;
  final double latitude;
  final double longitude;
}
