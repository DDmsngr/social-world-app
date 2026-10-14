import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/referrals/invites.dart';
import 'package:social_world/features/referrals/presentation/invite_code_dialog.dart';

Future<String?> _open(WidgetTester tester, Future<void> Function() interact) async {
  String? result;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await askInviteCode(
                context,
                title: 'Вас пригласили в ChaWo?',
                message: 'Введите код друга',
                cancelLabel: 'Пропустить',
              );
              done = true;
            },
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
  expect(find.text('Вас пригласили в ChaWo?'), findsOneWidget);
  expect(find.text('Введите код друга'), findsOneWidget);
  await interact();
  await tester.pumpAndSettle();
  expect(done, isTrue);
  return result;
}

void main() {
  testWidgets('введённый код возвращается заглавными', (tester) async {
    final code = await _open(tester, () async {
      await tester.enterText(find.byKey(const ValueKey('invite-code-field')), 'abc234');
      await tester.tap(find.text('Готово'));
    });
    expect(code, 'ABC234');
  });

  testWidgets('«Пропустить» ничего не возвращает', (tester) async {
    final code = await _open(tester, () async {
      await tester.tap(find.text('Пропустить'));
    });
    expect(code, isNull);
  });

  testWidgets('слишком короткий код — как отказ', (tester) async {
    final code = await _open(tester, () async {
      await tester.enterText(find.byKey(const ValueKey('invite-code-field')), 'ab12');
      await tester.tap(find.text('Готово'));
    });
    expect(code, isNull);
  });

  test('вопрос «Вас пригласили?» помнит, что его уже задавали', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PendingInvite.wasPrompted(), isFalse);
    await PendingInvite.markPrompted();
    expect(await PendingInvite.wasPrompted(), isTrue);
  });
}
