class NearbyPerson {
  const NearbyPerson({
    required this.id,
    required this.displayName,
    required this.blurredLatitude,
    required this.blurredLongitude,
    required this.blurRadiusMeters,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final double blurredLatitude;
  final double blurredLongitude;
  final double blurRadiusMeters;
}
