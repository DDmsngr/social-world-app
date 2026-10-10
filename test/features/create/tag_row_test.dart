import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/create/presentation/widgets/tag_row.dart';

void main() {
  testWidgets('теги добавляются подсказкой и вводом, счётчик считает до двух', (tester) async {
    var tags = <String>[];
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return TagRow(
                tags: tags,
                onChanged: (next) => rebuild(() => tags = next),
                suggestions: const ['закат', 'кофе', 'море'],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('нужно ещё 2'), findsOneWidget);
    await tester.tap(find.text('#закат'));
    await tester.pump();
    expect(tags, ['закат']);
    expect(find.text('нужно ещё 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '#Город ');
    await tester.pump();
    expect(tags, ['закат', 'город'], reason: 'пробел завершает тег, регистр и «#» убираются');
    expect(find.text('можно добавить ещё'), findsOneWidget);

    // Короткое и повторяющееся не добавляется.
    await tester.enterText(find.byType(TextField), 'а ');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'закат ');
    await tester.pump();
    expect(tags, ['закат', 'город']);
  });
}
