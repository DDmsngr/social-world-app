import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/links/deep_links.dart';
import 'package:social_world/features/profile/data/local_profile_repository.dart';
import 'package:social_world/features/profile/domain/profile_models.dart';
import 'package:social_world/features/profile/presentation/providers/profile_providers.dart';
import 'package:social_world/features/profile/presentation/widgets/mention_suggestions.dart';

class _People extends LocalProfileRepository {
  _People() : super(currentUserId: () => 'me');

  final queries = <String>[];

  @override
  Future<List<ProfileHit>> searchProfiles(String query) async {
    queries.add(query);
    return const [
      ProfileHit(id: 'v', displayName: 'Вика', username: 'vika'),
      ProfileHit(id: 'x', displayName: 'Без ника'),
    ];
  }
}

TextEditingValue _at(String text, [int? cursor]) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor ?? text.length));

void main() {
  group('где набирается @ник', () {
    test('после «@» в начале или после пробела — да', () {
      expect(mentionQueryAt(_at('@vi')), 'vi');
      expect(mentionQueryAt(_at('привет @vi')), 'vi');
      expect(mentionQueryAt(_at('привет @')), '');
    });

    test('почта, пробел после ника или курсор не у ника — нет', () {
      expect(mentionQueryAt(_at('mail@vi')), isNull);
      expect(mentionQueryAt(_at('@vika ')), isNull);
      expect(mentionQueryAt(_at('@vika привет', 2)), 'v');
      expect(mentionQueryAt(_at('просто текст')), isNull);
    });

    test('выбор подставляет «@ник » и ставит курсор за ним', () {
      final v = insertMention(_at('привет @vi, как дела', 10), 'vika');
      expect(v.text, 'привет @vika , как дела');
      expect(v.selection.baseOffset, 'привет @vika '.length);
      final end = insertMention(_at('пишу @v'), 'vika');
      expect(end.text, 'пишу @vika ');
    });
  });

  testWidgets('набрал @ви — подсказка людей с ником, тап вставляет ник', (tester) async {
    final people = _People();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(people)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: controller),
                MentionSuggestions(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'смотри @vi');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(people.queries.last, '@vi', reason: 'ищем по нику, не по имени');
    expect(find.text('Вика'), findsOneWidget);
    expect(find.text('Без ника'), findsNothing, reason: 'без ника упомянуть нельзя');

    await tester.tap(find.text('Вика'));
    await tester.pump();
    expect(controller.text, 'смотри @vika ');
    expect(find.byKey(const Key('mention-suggestions')), findsNothing);
  });

  test('уведомление об упоминании в блике ведёт на сам блик', () {
    expect(LinkTarget.fromSegment('story'), LinkTarget.story);
    expect(DeepLinks.locationFor(LinkTarget.story, 's1'), '/stories/s1');
  });
}
