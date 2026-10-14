import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/widgets/user_avatar.dart';

Border? _ringOf(WidgetTester tester) {
  final boxes = tester.widgetList<Container>(find.byType(Container));
  for (final box in boxes) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.border is Border) return decoration.border as Border;
  }
  return null;
}

void main() {
  tearDown(() => AvatarRings.set(const []));

  testWidgets('команда — золотая кайма, тестировщик — зелёная, остальные без', (tester) async {
    AvatarRings.set([
      {'profile_id': 'lesha', 'ring': 'gold'},
      {'profile_id': 'artur', 'ring': 'green'},
    ]);
    Future<void> show(String id) => tester.pumpWidget(
      MaterialApp(home: Center(child: UserAvatar(name: 'А', ringUserId: id))),
    );

    await show('lesha');
    expect(_ringOf(tester)?.top.color, AvatarRing.gold.color);
    await show('artur');
    expect(_ringOf(tester)?.top.color, AvatarRing.green.color);
    await show('vika');
    expect(_ringOf(tester), isNull);
  });

  testWidgets('список пришёл позже — кайма появляется без перерисовки экрана', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: UserAvatar(name: 'А', ringUserId: 'lesha'))));
    expect(_ringOf(tester), isNull);
    AvatarRings.set([
      {'profile_id': 'lesha', 'ring': 'gold'},
    ]);
    await tester.pump();
    expect(_ringOf(tester)?.top.color, AvatarRing.gold.color);
  });
}
