import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/media/photo_viewer.dart';

void main() {
  // Файла нет — внутри просмотрщика показывается заглушка, но жесты те же.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPhotoViewer(context, urls: const ['/нет-такого-файла.jpg']),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
  }

  double scale(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  testWidgets('щипок двумя пальцами увеличивает фото', (tester) async {
    await open(tester);
    expect(scale(tester), closeTo(1, 0.001));

    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(center - const Offset(30, 0));
    final second = await tester.startGesture(center + const Offset(30, 0));
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await first.moveTo(center - Offset(30.0 + i * 20, 0));
      await second.moveTo(center + Offset(30.0 + i * 20, 0));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(scale(tester), greaterThan(1.5));
  });

  testWidgets('свайп вниз одним пальцем закрывает неприближенное фото', (tester) async {
    await open(tester);
    expect(find.byType(PhotoViewer), findsOneWidget);

    final center = tester.getCenter(find.byType(InteractiveViewer));
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(center + Offset(0, i * 30.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewer), findsNothing);
  });
}
