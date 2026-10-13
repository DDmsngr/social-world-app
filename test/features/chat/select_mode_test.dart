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
import 'package:social_world/features/chat/presentation/providers/hidden_messages_provider.dart';

class _Repo extends LocalChatRepository {
  _Repo() : super(currentUserId: () => 'me');

  final controller = StreamController<List<ChatMessage>>();

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) => controller.stream;
}


Future<_Repo> _openChat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _Repo();
  addTearDown(repo.controller.close);
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
  repo.controller.add([
    for (var i = 0; i < 4; i++)
      ChatMessage(
        id: 'm$i',
        conversationId: 'conv-1',
        senderId: i.isEven ? 'person-1' : 'me',
        sentAt: DateTime(2026, 10, 1, 9, i),
        text: 'сообщение $i',
      ),
  ]);
  await tester.pump(const Duration(milliseconds: 300));
  return repo;
}

Future<void> _startPick(WidgetTester tester, String text) async {
  await tester.longPress(find.text(text));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Выбрать'));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('«Выбрать» включает выбор нескольких сообщений, крестик снимает', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    addTearDown(repo.controller.close);
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
    repo.controller.add([
      for (var i = 0; i < 4; i++)
        ChatMessage(
          id: 'm$i',
          conversationId: 'conv-1',
          senderId: i.isEven ? 'person-1' : 'me',
          sentAt: DateTime(2026, 10, 1, 9, i),
          text: 'сообщение $i',
        ),
    ]);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Выбрано'), findsNothing);

    await tester.longPress(find.text('сообщение 2'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Выбрать'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Выбрано: 1'), findsOneWidget);

    await tester.tap(find.text('сообщение 1'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Выбрано: 2'), findsOneWidget);

    // Тап по выбранному снимает его.
    await tester.tap(find.text('сообщение 1'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Выбрано: 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Отменить выбор'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Выбрано'), findsNothing);
  });

  testWidgets('массовое удаление: чужое скрывается у себя без вопросов, есть «Отменить»', (tester) async {
    await _openChat(tester);
    await _startPick(tester, 'сообщение 2');
    await tester.tap(find.text('сообщение 0'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Выбрано: 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pick-delete')));
    await tester.pump(const Duration(seconds: 1));
    // Оба чужие — спрашивать про «у всех» нечего.
    expect(find.textContaining('Удалить 2'), findsNothing);
    expect(find.text('Скрыто у вас: 2'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    expect(container.read(hiddenMessagesProvider), {'m0', 'm2'});
    expect(find.textContaining('Выбрано'), findsNothing);

    // Кнопка снекбара лежит под нижней панелью теста — жмём её обработчик.
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(hiddenMessagesProvider), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('массовое удаление своих и чужих: диалог «у всех», потом сообщения исчезают', (tester) async {
    await _openChat(tester);
    await _startPick(tester, 'сообщение 1');
    await tester.tap(find.text('сообщение 2'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('pick-delete')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Удалить 2 сообщения?'), findsOneWidget);
    expect(find.textContaining('1 из 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Удалить 2 сообщения?'), findsNothing);
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    expect(container.read(hiddenMessagesProvider), {'m1', 'm2'});
    expect(find.textContaining('Выбрано'), findsNothing);
    // Хвосты таймеров экрана и отправки дорабатывают до конца теста.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
