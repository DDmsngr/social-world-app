import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/data/local_auth_repository.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/auth/presentation/screens/age_screen.dart';
import 'package:social_world/features/auth/presentation/widgets/birth_date_field.dart';

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

    // Набираем только цифры — точки встают сами.
    await tester.enterText(find.byKey(const Key('birth-date-field')), '1503');
    await tester.pump();
    expect(find.text('15.03'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'дата ещё не полная');
    await tester.enterText(find.byKey(const Key('birth-date-field')), '15032000');
    await tester.pump();

    expect(find.text('15.03.2000'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.currentUser!.birthDate, DateTime(2000, 3, 15));
  });

  testWidgets('несуществующая дата — подсказка и кнопка неактивна', (tester) async {
    final repository = LocalAuthRepository();
    await repository.devSignIn(displayName: 'Аня');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AgeScreen()),
      ),
    );
    await tester.enterText(find.byKey(const Key('birth-date-field')), '31022000');
    await tester.pump();
    expect(find.text('Такой даты нет'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('age-save'))).onPressed, isNull);
  });

  test('разбор даты: только настоящие и не из будущего', () {
    final now = DateTime(2026, 10, 14);
    expect(BirthDateField.parse('08.07.1987', now: now), DateTime(1987, 7, 8));
    expect(BirthDateField.parse('29.02.2001', now: now), isNull);
    expect(BirthDateField.parse('15.10.2026', now: now), isNull);
    expect(BirthDateField.parse('01.01.1900', now: now), isNull);
    expect(BirthDateField.parse('08.07', now: now), isNull);
  });

  test('дата рождения задаётся один раз: повтор ничего не меняет', () async {
    final repository = LocalAuthRepository();
    await repository.devSignIn(displayName: 'Аня');
    await repository.setBirthDate(DateTime(2000, 3, 15));
    final again = await repository.setBirthDate(DateTime(2012, 1, 1));
    expect(again.birthDate, DateTime(2000, 3, 15));
  });
}
