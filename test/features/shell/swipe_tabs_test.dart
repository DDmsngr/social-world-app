import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/shell/presentation/swipe_tabs.dart';

void main() {
  // Ветки: 0 Flow, 1 Pulse (карта), 2 Создать, 3 Чаты, 4 Профиль.
  test('свайп идёт Flow → Создать → Чаты → Профиль и обратно', () {
    expect(swipeTarget(0, forward: true), 2);
    expect(swipeTarget(2, forward: true), 3);
    expect(swipeTarget(3, forward: true), 4);
    expect(swipeTarget(4, forward: false), 3);
    expect(swipeTarget(3, forward: false), 2);
    expect(swipeTarget(2, forward: false), 0);
  });

  test('на краях свайпать некуда', () {
    expect(swipeTarget(0, forward: false), isNull);
    expect(swipeTarget(4, forward: true), isNull);
  });

  test('карта — исключение: с неё не уйти и на неё не попасть свайпом', () {
    expect(swipeTarget(1, forward: true), isNull);
    expect(swipeTarget(1, forward: false), isNull);
    for (final tab in [0, 2, 3, 4]) {
      expect(swipeTarget(tab, forward: true), isNot(1));
      expect(swipeTarget(tab, forward: false), isNot(1));
    }
  });
}
