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

void main() {
  testWidgets('панель реакций появляется у самого сообщения', (tester) async {
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
      for (var i = 0; i < 12; i++)
        ChatMessage(
          id: 'm$i',
          conversationId: 'conv-1',
          senderId: i.isEven ? 'person-1' : 'me',
          sentAt: DateTime(2026, 10, 1, 9, i),
          text: 'сообщение $i',
        ),
    ]);
    await tester.pump(const Duration(milliseconds: 300));

    final bubble = tester.getRect(find.text('сообщение 7'));
    await tester.longPress(find.text('сообщение 7'));
    await tester.pump(const Duration(milliseconds: 400));
    final more = tester.getRect(find.bySemanticsLabel('Все реакции'));
    expect((more.center.dy - bubble.center.dy).abs(), lessThan(200),
        reason: 'панель рядом с сообщением, а не посреди экрана');
  });
}
