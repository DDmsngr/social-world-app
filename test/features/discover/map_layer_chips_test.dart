import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/discover/presentation/widgets/map_controls.dart';

// Чип «Моменты» на карте торчал за край экрана обрубком: строка чипов была
// горизонтальной прокруткой, а четыре слоя шире экрана. Теперь Wrap — ни один
// чип не должен выходить за ширину, даже на узком телефоне.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('все чипы слоёв помещаются в $width dp', (tester) async {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: MapLayerChips(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(4));
      for (final chip in chips.evaluate()) {
        final box = chip.renderObject! as RenderBox;
        final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
        expect(right, lessThanOrEqualTo(width - 20 + 0.5),
            reason: 'чип выходит за край экрана шириной $width');
      }
    });
  }
}
