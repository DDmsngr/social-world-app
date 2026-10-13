import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/presentation/widgets/chat_composer.dart';

Future<(List<String>, Finder)> _pump(WidgetTester tester) async {
  final events = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoldToRecordButton(
            icon: Icons.mic,
            label: 'запись',
            onTap: () => events.add('tap'),
            onHold: () => events.add('hold'),
          ),
        ),
      ),
    ),
  );
  return (events, find.byType(HoldToRecordButton));
}

void main() {
  testWidgets('короткий тап переключает режим и не начинает запись', (tester) async {
    final (events, button) = await _pump(tester);
    await tester.tap(button);
    await tester.pump();
    expect(events, ['tap']);
  });

  testWidgets('удержание меньше 0,6 секунды записи не начинает', (tester) async {
    final (events, button) = await _pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(events, ['tap']);
  });

  testWidgets('удержание 0,6 секунды начинает запись, отпускание ничего не добавляет', (tester) async {
    final (events, button) = await _pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(); // анимация стартует с первого кадра
    await tester.pump(const Duration(milliseconds: 700));
    expect(events, ['hold']);
    await gesture.up();
    await tester.pump();
    expect(events, ['hold']);
  });
}
