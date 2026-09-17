import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/routes_providers.dart';
import '../route_recorder_screen.dart'
    show formatRouteDistance, formatRouteDuration;
import 'route_map_marker.dart';
import 'route_sketch.dart';

/// Карточка маршрута внутри поста ленты.
class RoutePostPreview extends ConsumerWidget {
  const RoutePostPreview({super.key, required this.routeId});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider(routeId));

    return InkWell(
      onTap: () => context.push('${Routes.routes}/$routeId'),
      child: SizedBox(
        height: 190,
        child: route.when(
          data: (data) => Stack(
            fit: StackFit.expand,
            children: [
              RouteSketch(
                path: data.path,
                padding: 18,
                markers: [
                  for (final photo in data.photos)
                    RouteMapMarker(
                      latitude: photo.latitude,
                      longitude: photo.longitude,
                    ),
                ],
              ),
              Positioned(
                left: 14,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hair),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timeline,
                          size: 15,
                          color: AppColors.primaryTint,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '${formatRouteDistance(data.distanceMeters)} · '
                          '${formatRouteDuration(data.duration)}'
                          '${data.photos.isEmpty ? '' : ' · ${data.photos.length} фото'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          loading: () => const ColoredBox(
            color: AppColors.ink,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryTint,
                ),
              ),
            ),
          ),
          error: (_, _) => const ColoredBox(
            color: AppColors.ink,
            child: Center(
              child: Text(
                'Маршрут недоступен',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
