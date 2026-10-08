import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/presentation/chat_screen.dart';
import 'package:social_world/features/chat/presentation/providers/chat_providers.dart';

class _Repo extends LocalChatRepository {
  _Repo() : super(currentUserId: () => 'me');

  final controller = StreamController<List<ChatMessage>>();

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) => controller.stream;
}

ChatMessage _msg(String id, String text, {String sender = 'person-1', DateTime? at}) => ChatMessage(
  id: id,
  conversationId: 'conv-1',
  senderId: sender,
  sentAt: at ?? DateTime(2026, 10, 1, 9, 0),
  text: text,
);

void main() {
  late _Repo repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _Repo();
  });
  tearDown(() => repo.controller.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWithValue(const AppUser(id: 'me', displayName: 'Алексей')),
        ],
        child: const MaterialApp(home: ChatScreen(conversationId: 'conv-1', peerName: 'Алина')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('удалённое сообщение ещё мгновение на месте, потом исчезает', (tester) async {
    await open(tester);
    final first = _msg('a', 'первое');
    final second = _msg('b', 'второе');
    repo.controller.add([first, second]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('второе'), findsOneWidget);

    // Сообщение удалили (у себя или у всех): в списке его больше нет.
    repo.controller.add([first]);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('второе'), findsOneWidget, reason: 'растворяется на своём месте');
    expect(find.text('первое'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('второе'), findsNothing, reason: 'после эффекта пропало совсем');
    expect(find.text('первое'), findsOneWidget);
  });

  testWidgets('своё новое сообщение появляется с анимацией и остаётся на экране', (tester) async {
    await open(tester);
    repo.controller.add([_msg('a', 'старое')]);
    await tester.pump(const Duration(milliseconds: 100));

    repo.controller.add([
      _msg('a', 'старое'),
      _msg('b', 'новое', sender: 'me', at: DateTime.now()),
    ]);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('новое'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('новое'), findsOneWidget);
  });
}
