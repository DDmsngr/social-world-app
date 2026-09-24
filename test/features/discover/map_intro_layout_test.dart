import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/discover/presentation/widgets/map_controls.dart';

// Регрессия на пустой Pulse (22–24.09). MapIntro сам возвращал Positioned.fill,
// когда виден, и SizedBox.shrink, когда нет. SizedBox.shrink — это
// НЕпозиционированный ребёнок Stack нулевого размера, а RenderStack при
// наличии хотя бы одного такого ребёнка берёт размер по нему, а не по
// родителю. Экран схлопывался в 0×0 и обрезал всё: карту, поиск, чипы.
// Выглядело как «карта не работает», искали полдня не там.
void main() {
  const mapKey = Key('map');

  Future<Size> pumpMap(WidgetTester tester, {required bool introSeen}) async {
    SharedPreferences.setMockInitialValues({'map_intro_seen_v1': introSeen});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: ColoredBox(color: Color(0xFF000000), key: mapKey)),
              Positioned.fill(child: MapIntro()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byKey(mapKey));
  }

  testWidgets('карта занимает весь экран, когда интро уже показывали', (tester) async {
    final size = await pumpMap(tester, introSeen: true);
    expect(size.width, greaterThan(100));
    expect(size.height, greaterThan(100));
  });

  testWidgets('карта занимает весь экран, когда интро ещё не показывали', (tester) async {
    final size = await pumpMap(tester, introSeen: false);
    expect(size.width, greaterThan(100));
    expect(size.height, greaterThan(100));
    expect(find.text('Дальше'), findsOneWidget, reason: 'интро должно быть видно');
  });
}
