import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/core/network/vpn_check.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';
import 'package:social_world/features/chat/presentation/providers/chat_providers.dart';
import 'package:social_world/features/chat/presentation/widgets/chat_composer.dart';

/// Репозиторий, у которого первая отправка «зависает»: запрос ушёл, ответа нет
/// (слабая связь). Остальные проходят.
class _FlakyRepository extends LocalChatRepository {
  _FlakyRepository() : super(currentUserId: () => 'me');

  final ids = <String?>[];
  var hangFirst = true;

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  }) {
    ids.add(options.messageId);
    if (hangFirst && ids.length == 1) return Completer<ChatMessage>().future;
    return super.send(conversationId: conversationId, text: text, kind: kind, options: options);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    vpnCheckOverride = () async => false;
  });
  tearDown(() => vpnCheckOverride = null);

  Future<_FlakyRepository> pump(WidgetTester tester) async {
    final repository = _FlakyRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repository),
          currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: ChatComposer(conversationId: 'conv-1'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> send(WidgetTester tester, [String? text]) async {
    if (text != null) await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
  }


  /// Тайм-аут отправки: после него обработчик проверяет VPN, в тесте — «нет».
  Future<void> letSendTimeOut(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
  }

  testWidgets('тайм-аут и повторная отправка того же текста идут с одним id: дубля не будет', (tester) async {
    final repository = await pump(tester);

    await send(tester, 'привет');
    await letSendTimeOut(tester);
    expect(find.textContaining('Сервер не ответил'), findsOneWidget);

    await send(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(repository.ids, hasLength(2));
    expect(repository.ids.first, isNotNull);
    expect(repository.ids.last, repository.ids.first);
  });

  testWidgets('успешная отправка не оставляет id: следующее сообщение — новое', (tester) async {
    final repository = await pump(tester);
    repository.hangFirst = false;

    await send(tester, 'раз');
    await tester.pump(const Duration(seconds: 1));
    await send(tester, 'раз');
    await tester.pump(const Duration(seconds: 1));

    expect(repository.ids, hasLength(2));
    expect(repository.ids.first, isNot(repository.ids.last), reason: 'два осознанных «раз» — два сообщения');
  });

  testWidgets('изменили текст после сбоя — это уже другое сообщение, id новый', (tester) async {
    final repository = await pump(tester);

    await send(tester, 'привет');
    await letSendTimeOut(tester);
    await send(tester, 'привет, как дела');
    await tester.pump(const Duration(seconds: 1));

    expect(repository.ids, hasLength(2));
    expect(repository.ids.first, isNot(repository.ids.last));
  });
}
