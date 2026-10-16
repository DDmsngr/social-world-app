import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../domain/entities/place.dart';
import 'providers/discover_providers.dart';

/// Место, карточку которого карта должна открыть, когда до неё дойдёт: пост
/// переключает вкладку, а шторку открывает сам экран карты. Карта грузит
/// места только вокруг выбранного города, поэтому точку из другого города
/// иначе было бы не увидеть, а так карточка открывается в любом случае.
class PendingPlaceController extends Notifier<Place?> {
  @override
  Place? build() {
    ref.keepAlive();
    return null;
  }

  void show(Place place) => state = place;

  /// Забирает место один раз: повторный заход на карту шторку не откроет.
  Place? take() {
    final place = state;
    state = null;
    return place;
  }
}

final pendingPlaceProvider = NotifierProvider<PendingPlaceController, Place?>(
  PendingPlaceController.new,
);

/// Открыть место на карте ChaWo: камера на точку, карточка места поверх.
void showPlaceOnMap(BuildContext context, WidgetRef ref, Place place) {
  ref.read(mapFocusProvider.notifier).request(place.latitude, place.longitude, zoom: 16);
  ref.read(pendingPlaceProvider.notifier).show(place);
  context.go(Routes.home);
}
