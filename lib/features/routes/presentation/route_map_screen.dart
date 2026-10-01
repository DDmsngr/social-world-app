import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_viewer.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/entities/city_route.dart';
import 'providers/routes_providers.dart';
import 'route_recorder_screen.dart' show formatRouteDistance, formatRouteDuration;
import 'widgets/route_map.dart';
import 'widgets/route_map_marker.dart';

/// Маршрут на весь экран: путь на карте и круглые превью фотографий там, где
/// они сняты. Нажатие на кружок открывает фото, листать можно между всеми
/// фотографиями маршрута.
class RouteMapScreen extends ConsumerWidget {
  const RouteMapScreen({super.key, required this.routeId});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider(routeId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: CircleAvatar(
            backgroundColor: AppColors.ink.withValues(alpha: 0.78),
            child: IconButton(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('${Routes.routes}/$routeId'),
              tooltip: 'Назад',
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
      ),
      body: route.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(routeProvider(routeId)),
            child: const Text('Повторить'),
          ),
        ),
        data: (data) => _Body(route: data),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.route});

  final CityRoute route;

  @override
  Widget build(BuildContext context) {
    final photos = route.photos;
    return Stack(
      children: [
        Positioned.fill(
          child: RouteMap(
            path: route.path,
            markers: [
              for (final photo in photos)
                RouteMapMarker(
                  latitude: photo.latitude,
                  longitude: photo.longitude,
                  photoUrl: photo.photoUrl,
                ),
            ],
            onMarkerTap: (index) => showPhotoViewer(
              context,
              urls: [for (final p in photos) p.photoUrl],
              captions: [for (final p in photos) p.caption],
              initialIndex: index,
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.ink.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.hair),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          route.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatRouteDistance(route.distanceMeters)} · '
                          '${formatRouteDuration(route.duration)}'
                          '${photos.isEmpty ? '' : ' · ${photos.length} фото'}',
                          style: TextStyle(fontSize: 12, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ),
                  if (photos.isNotEmpty)
                    Text(
                      'Нажмите на кружок',
                      style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
