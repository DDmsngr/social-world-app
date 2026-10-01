import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/photo_viewer.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../domain/entities/city_route.dart';
import 'providers/routes_providers.dart';
import 'route_recorder_screen.dart' show formatRouteDistance, formatRouteDuration;
import 'widgets/route_map.dart';
import 'widgets/route_map_marker.dart';

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({super.key, required this.routeId});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider(routeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Маршрут'),
        // Сразу после публикации экран открыт поверх пустого стека: кнопки
        // «назад» у AppBar не будет, и выйти отсюда стало бы некуда.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.feed),
        ),
      ),
      body: route.when(
        data: (data) => _RouteBody(route: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Маршрут не открылся', style: AppTypography.serif(26)),
                const SizedBox(height: 8),
                Text(
                  'Возможно, автор его удалил.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => ref.invalidate(routeProvider(routeId)),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteBody extends StatelessWidget {
  const _RouteBody({required this.route});

  final CityRoute route;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Карта здесь превью: прокручивая страницу, пальцем её легко сдвинуть
        // случайно. Поэтому прозрачная плёнка сверху ловит касание и открывает
        // карту на весь экран, где уже можно двигать, масштабировать и
        // нажимать на фото.
        SizedBox(
          height: 320,
          child: Stack(
            children: [
              Positioned.fill(
                child: RouteMap(
                  path: route.path,
                  markers: [
                    for (final photo in route.photos)
                      RouteMapMarker(
                        latitude: photo.latitude,
                        longitude: photo.longitude,
                        photoUrl: photo.photoUrl,
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: 'Открыть карту на весь экран',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('${Routes.routes}/${route.id}/map'),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.hair),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_full, size: 14, color: AppColors.primaryTint),
                          const SizedBox(width: 6),
                          Text(
                            'На весь экран',
                            style: TextStyle(fontSize: 12, color: AppColors.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Прогулка'),
              const SizedBox(height: 12),
              Text(route.title, style: AppTypography.serif(30)),
              const SizedBox(height: 10),
              Text(
                '${route.authorName} · '
                '${formatRouteDistance(route.distanceMeters)} · '
                '${formatRouteDuration(route.duration)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (route.photos.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionLabel('Фото на пути'),
                const SizedBox(height: 12),
                for (var i = 0; i < route.photos.length; i++) ...[
                  GestureDetector(
                    onTap: () => showPhotoViewer(
                      context,
                      urls: [for (final p in route.photos) p.photoUrl],
                      captions: [for (final p in route.photos) p.caption],
                      initialIndex: i,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: _RoutePhotoView(url: route.photos[i].photoUrl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// В моках фото остаётся файлом на устройстве, на бэкенде — ссылкой в Storage.
class _RoutePhotoView extends StatelessWidget {
  const _RoutePhotoView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => ColoredBox(color: AppColors.ink2),
        errorWidget: (_, _, _) => ColoredBox(
          color: AppColors.ink2,
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: AppColors.textFaint),
          ),
        ),
      );
    }

    return Image.file(File(url), fit: BoxFit.cover);
  }
}
