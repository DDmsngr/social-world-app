import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/domain/entities/place.dart';
import 'package:social_world/features/discover/presentation/show_on_map.dart';

void main() {
  const place = Place(id: 'p1', title: 'Сочинский цирк', latitude: 43.5689, longitude: 39.7383);

  test('карточка места из поста открывается один раз', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pending = container.read(pendingPlaceProvider.notifier);

    pending.show(place);
    expect(pending.take()?.title, 'Сочинский цирк');
    // Повторный заход на карту шторку уже не открывает.
    expect(pending.take(), isNull);
  });
}
