import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/feed/domain/entities/post.dart';
import 'package:social_world/features/feed/presentation/post_detail_screen.dart';

// Веб-прогон через Playwright в это поле печатать не умеет (Flutter не
// синхронизирует нижний композер со скрытым textarea), поэтому путь
// «написал → отправил → увидел в ветке» проверяется здесь.
void main() {
  final post = Post(
    id: 'seed-1',
    authorId: 'person-1',
    authorName: 'Алина',
    kind: PostKind.text,
    body: 'Закат на Приморской.',
    createdAt: DateTime.now(),
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PostDetailScreen(postId: post.id, post: post),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('ветка из заглушки показывается с вложенностью', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Вода реально тёплая? Собираюсь завтра с утра.'), findsOne);
    expect(find.text('Двадцать два, для сентября отлично.'), findsOne);
    expect(find.text('Тогда буду.'), findsOne);
  });

  testWidgets('комментарий отправляется и появляется в ветке', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'Новый комментарий');
    await tester.tap(find.byTooltip('Отправить'));
    // Отправка задевает и ленту (счётчик комментариев на карточке), у неё свой
    // таймер в заглушке — ждём, пока оба доедут.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Новый комментарий'), findsOne);
  });

  testWidgets('свёрнутая ветка прячет ответы', (tester) async {
    await pumpScreen(tester);

    // Имя ведёт в профиль, а свернуть ветку можно любым другим местом её
    // шапки — берём пустой правый край строки.
    final header = find.ancestor(
      of: find.text('Саша').first,
      matching: find.byType(InkWell),
    ).first;
    await tester.tapAt(tester.getTopRight(header) + const Offset(-6, 10));
    await tester.pump();

    expect(find.text('Вода реально тёплая? Собираюсь завтра с утра.'), findsNothing);
    expect(find.text('Двадцать два, для сентября отлично.'), findsNothing);
    // Соседняя корневая ветка сворачиванием не задета.
    expect(find.text('Там же сейчас стройка на входе, как прошли?'), findsOne);
  });
}
