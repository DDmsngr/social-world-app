import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/presentation/providers/discover_providers.dart';

void main() {
  // В тестах платформенного геолокатора нет — вызов падает MissingPluginException.
  // Это тот же путь, что на вебе и при отозванном разрешении: карта обязана
  // открыться на центре пилота, а не зависнуть и не уронить экран.
  test('без позиции устройства центром остаётся Сочи', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final center = await container.read(discoverCenterProvider.future);

    expect(center.latitude, discoverCenterLatitude);
    expect(center.longitude, discoverCenterLongitude);
  });
}
