import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/needs/presentation/need_detail_screen.dart';
import 'package:social_world/features/quests/presentation/my_quests_screen.dart';
import 'package:social_world/features/quests/presentation/quest_detail_screen.dart';
import 'package:social_world/features/quests/presentation/quest_rules_screen.dart';

// Экраны целиком на заглушках (без сервера): сценарий проходится руками,
// а вёрстка не должна переполняться на узком телефоне.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget screen, {double width = 360}) async {
    tester.view.physicalSize = Size(width * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AppUser(id: 'me', displayName: 'Я'),
          ),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('карточка квеста: заявка меняет кнопку', (tester) async {
    await pump(tester, const QuestDetailScreen(questId: 'seed-quest-coffee'));

    expect(find.text('10 бесплатных кофе от «Кофе у Серёги»'), findsOne);
    expect(find.text('Участники: 3/10'), findsOne);
    // Чужим список участников не показывается (п. 44). SectionLabel пишет
    // заголовки заглавными — ищем именно так, иначе проверка пустая.
    expect(find.text('КТО УЧАСТВУЕТ'), findsNothing);

    await tester.ensureVisible(find.text('Подать заявку'));
    await tester.tap(find.text('Подать заявку'));
    await tester.pumpAndSettle();

    expect(find.text('Заявка отправлена'), findsWidgets);
    expect(find.text('Отозвать заявку'), findsOne);
  });

  testWidgets('квест без лимита: сразу участник, видны соучастники', (tester) async {
    await pump(tester, const QuestDetailScreen(questId: 'seed-quest-bike'));

    await tester.ensureVisible(find.text('Участвовать'));
    await tester.tap(find.text('Участвовать'));
    await tester.pumpAndSettle();

    expect(find.text('Завершить квест'), findsOne);
    expect(find.text('Отказаться'), findsOne);
    // Список ленивый: нижние секции строятся, только когда до них долистали.
    await tester.scrollUntilVisible(find.text('КТО УЧАСТВУЕТ'), 200);
    expect(find.text('КТО УЧАСТВУЕТ'), findsOne);
  });

  testWidgets('QR с неверным кодом — понятная ошибка, без падения', (tester) async {
    await pump(
      tester,
      const QuestDetailScreen(questId: 'seed-quest-bike', arrivalCode: 'AAAA2222'),
    );
    expect(find.text('Код не подходит. Уточните его у организатора'), findsOne);
  });

  testWidgets('QR с верным кодом отмечает прибытие', (tester) async {
    await pump(
      tester,
      const QuestDetailScreen(questId: 'seed-quest-bike', arrivalCode: 'BIKE2345'),
    );
    expect(find.text('Вы на месте. Хорошего квеста!'), findsOne);
    expect(find.text('Вы на месте'), findsOne);
  });

  testWidgets('несуществующий квест — понятное сообщение', (tester) async {
    await pump(tester, const QuestDetailScreen(questId: 'no-such-quest'));
    expect(find.text('Квест недоступен'), findsOne);
  });

  testWidgets('правила: «Принять» только с галочкой', (tester) async {
    await pump(tester, const QuestRulesScreen(), width: 320);

    FilledButton accept() => tester.widget<FilledButton>(
      find.ancestor(of: find.text('Принять'), matching: find.byType(FilledButton)),
    );
    await tester.scrollUntilVisible(find.text('Принять'), 200);
    expect(accept().onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(accept().onPressed, isNotNull);
  });

  testWidgets('«Квесты» в профиле: три раздела', (tester) async {
    await pump(tester, const MyQuestsScreen(), width: 320);
    expect(find.text('Активные'), findsOne);
    expect(find.text('История'), findsOne);
    expect(find.text('Созданные мной'), findsOne);
    expect(find.text('Активных квестов нет'), findsOne);
  });

  testWidgets('просьба: отклик «Могу помочь»', (tester) async {
    await pump(tester, const NeedDetailScreen(needId: 'seed-need-tv'));
    expect(find.text('Нужно повесить телевизор на стену, кронштейн есть'), findsOne);
    expect(find.text('Пока никто не откликнулся.'), findsOne);

    await tester.tap(find.text('Могу помочь'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Могу вечером');
    await tester.tap(find.text('Откликнуться'));
    await tester.pumpAndSettle();

    expect(find.text('Могу вечером'), findsOne);
    expect(find.text('Вы откликнулись · отозвать'), findsOne);
  });
}
