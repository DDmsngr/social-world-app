import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/data/local_auth_repository.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/auth/presentation/screens/age_screen.dart';

void main() {
  testWidgets('экран возраста: без даты не продолжить, с датой — сохраняет и называет год', (tester) async {
    final repository = LocalAuthRepository();
    await repository.devSignIn(displayName: 'Аня');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AgeScreen()),
      ),
    );

    final save = find.byKey(const Key('age-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.byKey(const Key('birth-date-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '03/15/2000');
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();

    expect(find.text('15.03.2000'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.currentUser!.birthDate, DateTime(2000, 3, 15));
  });

  test('дата рождения задаётся один раз: повтор ничего не меняет', () async {
    final repository = LocalAuthRepository();
    await repository.devSignIn(displayName: 'Аня');
    await repository.setBirthDate(DateTime(2000, 3, 15));
    final again = await repository.setBirthDate(DateTime(2012, 1, 1));
    expect(again.birthDate, DateTime(2000, 3, 15));
  });
}
