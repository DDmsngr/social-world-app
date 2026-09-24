import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/quests/domain/entities/quest.dart';
import 'package:social_world/features/quests/presentation/widgets/quest_action_panel.dart';

// Кнопки карточки квеста по ТЗ (п. 22, 23): до заявки — «Подать заявку»,
// после одобрения — «Завершить квест», «Построить маршрут» и «Отказаться».
void main() {
  Quest quest({
    QuestParticipationStatus? myStatus,
    int? limit = 10,
    int taken = 3,
    String author = 'organizer',
    QuestStatus status = QuestStatus.active,
  }) => Quest(
    id: 'q1',
    authorId: author,
    authorName: 'Кофе у Серёги',
    title: '10 бесплатных кофе',
    latitude: 43.58,
    longitude: 39.72,
    startsAt: DateTime.now(),
    createdAt: DateTime.now(),
    maxParticipants: limit,
    participantCount: taken,
    myStatus: myStatus,
    status: status,
  );

  Future<void> pump(WidgetTester tester, Quest quest, {String me = 'lev'}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(AppUser(id: me))],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: QuestActionPanel(quest: quest)),
          ),
        ),
      ),
    );
  }

  testWidgets('до заявки — «Подать заявку» и маршрут', (tester) async {
    await pump(tester, quest());
    expect(find.text('Подать заявку'), findsOne);
    expect(find.text('Построить маршрут'), findsOne);
    expect(find.text('Завершить квест'), findsNothing);
  });

  testWidgets('без лимита — «Участвовать»', (tester) async {
    await pump(tester, quest(limit: null));
    expect(find.text('Участвовать'), findsOne);
  });

  testWidgets('мест нет — кнопка неактивна', (tester) async {
    await pump(tester, quest(limit: 3, taken: 3));
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Мест нет'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('заявка отправлена — можно отозвать', (tester) async {
    await pump(tester, quest(myStatus: QuestParticipationStatus.requested));
    expect(find.text('Заявка отправлена'), findsOne);
    expect(find.text('Отозвать заявку'), findsOne);
  });

  testWidgets('после одобрения — «Завершить квест», код и «Отказаться»', (tester) async {
    await pump(tester, quest(myStatus: QuestParticipationStatus.approved));
    expect(find.text('Завершить квест'), findsOne);
    expect(find.text('Я на месте — ввести код'), findsOne);
    expect(find.text('Построить маршрут'), findsOne);
    expect(find.text('Отказаться'), findsOne);
    expect(find.text('Подать заявку'), findsNothing);
  });

  testWidgets('на месте — ввода кода больше нет', (tester) async {
    await pump(tester, quest(myStatus: QuestParticipationStatus.arrived));
    expect(find.text('Вы на месте'), findsOne);
    expect(find.text('Завершить квест'), findsOne);
    expect(find.text('Я на месте — ввести код'), findsNothing);
  });

  testWidgets('организатор видит QR, а не заявку', (tester) async {
    await pump(tester, quest(), me: 'organizer');
    expect(find.text('Вы организатор'), findsOne);
    expect(find.text('Показать QR прибытия'), findsOne);
    expect(find.text('Подать заявку'), findsNothing);
  });

  testWidgets('завершённый квест — без заявки и маршрута', (tester) async {
    await pump(tester, quest(status: QuestStatus.finished));
    expect(find.text('Квест завершён'), findsOne);
    expect(find.text('Подать заявку'), findsNothing);
    expect(find.text('Построить маршрут'), findsNothing);
  });

  testWidgets('после участия можно добавить момент', (tester) async {
    await pump(tester, quest(myStatus: QuestParticipationStatus.completed));
    expect(find.text('Вы завершили участие'), findsOne);
    expect(find.text('Добавить момент'), findsOne);
  });
}
