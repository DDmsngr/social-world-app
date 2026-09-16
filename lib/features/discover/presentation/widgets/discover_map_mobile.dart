import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/place.dart';

class DiscoverMap extends StatelessWidget {
  const DiscoverMap({
    super.key,
    required this.data,
    required this.places,
    required this.onPlaceTap,
  });

  final DiscoverSnapshot data;
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const _MobileMapUnavailable(
        title: 'Карта доступна на Android и iOS',
        text: 'Откройте этот раздел в мобильном приложении.',
      );
    }
    if (Env.yandexMapkitApiKey.isEmpty) {
      return const _MobileMapUnavailable(
        title: 'Карта почти готова',
        text:
            'Добавьте YANDEX_MAPKIT_API_KEY в .env и перезапустите приложение.',
      );
    }

    return YandexMap(
      nightModeEnabled: true,
      mode2DEnabled: true,
      mapObjects: _mapObjects(),
      onMapCreated: (controller) => controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: Point(
              latitude: data.centerLatitude,
              longitude: data.centerLongitude,
            ),
            zoom: 14.5,
          ),
        ),
        animation: const MapAnimation(
          type: MapAnimationType.smooth,
          duration: 0.6,
        ),
      ),
    );
  }

  List<MapObject> _mapObjects() => [
    CircleMapObject(
      mapId: const MapObjectId('district-pulse'),
      circle: Circle(
        center: Point(
          latitude: data.centerLatitude,
          longitude: data.centerLongitude,
        ),
        radius: 280 + data.people.length * 55,
      ),
      strokeColor: AppColors.primary.withValues(alpha: 0.55),
      strokeWidth: 2,
      fillColor: AppColors.primary.withValues(
        alpha: 0.035 + data.pulseLevel * 0.025,
      ),
      zIndex: 0,
    ),
    for (final person in data.people)
      CircleMapObject(
        mapId: MapObjectId('person-${person.id}'),
        circle: Circle(
          center: Point(
            latitude: person.blurredLatitude,
            longitude: person.blurredLongitude,
          ),
          radius: person.blurRadiusMeters,
        ),
        // Зоны людей — холодным geo: бордовый на карте занят пульсом района,
        // и если красить им же метки, они читаются как кнопки.
        strokeColor: AppColors.geo.withValues(alpha: 0.7),
        strokeWidth: 1.5,
        fillColor: AppColors.geo.withValues(alpha: 0.18),
        zIndex: 1,
      ),
    for (final place in places)
      PlacemarkMapObject(
        mapId: MapObjectId('place-${place.id}'),
        point: Point(latitude: place.latitude, longitude: place.longitude),
        opacity: 1,
        zIndex: 3,
        consumeTapEvents: true,
        text: PlacemarkText(
          text: place.title,
          style: const PlacemarkTextStyle(
            placement: TextStylePlacement.bottom,
            offset: 8,
            size: 11,
            color: AppColors.text,
            outlineColor: AppColors.ink,
          ),
        ),
        onTap: (_, _) => onPlaceTap(place),
      ),
  ];
}

class _MobileMapUnavailable extends StatelessWidget {
  const _MobileMapUnavailable({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Карта'),
              const SizedBox(height: 12),
              Text(title, style: AppTypography.serif(28)),
              const SizedBox(height: 8),
              Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
