import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/conversation.dart';
import 'package:social_world/features/chat/presentation/providers/chat_providers.dart';
import 'package:social_world/features/chat/presentation/providers/hidden_messages_provider.dart';
import 'package:social_world/features/chat/presentation/widgets/chat_composer.dart';
import 'package:social_world/features/chat/presentation/widgets/message_bubble.dart';
import 'package:social_world/features/chat/presentation/widgets/message_menu.dart';
import 'package:social_world/features/shell/presentation/home_shell.dart';

class _SpyRepository extends LocalChatRepository {
  _SpyRepository() : super(currentUserId: () => 'me');

  final sent = <String>[];

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
  }) {
    sent.add(text);
    return super.send(conversationId: conversationId, text: text, kind: kind);
  }
}

void main() {
  late _SpyRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = _SpyRepository();
  });
  tearDown(() => repository.dispose());

  Widget app(Widget child) => ProviderScope(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
      currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('эмодзи встаёт в текст и ничего не отправляет', (tester) async {
    await tester.pumpWidget(
      app(
        const Align(
          alignment: Alignment.bottomCenter,
          child: ChatComposer(conversationId: 'conv-1'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Привет');
    await tester.tap(find.byTooltip('Эмодзи'));
    await tester.pumpAndSettle();
    // 😀 — ещё и иконка вкладки, поэтому жмём соседний в первом ряду.
    await tester.tap(find.text('😃'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Привет😃');
    expect(repository.sent, isEmpty);

    // Панель закрывается обратно на клавиатуру той же кнопкой.
    await tester.tap(find.byTooltip('Клавиатура'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Эмодзи'), findsOneWidget);
  });

  testWidgets('отправка текста очищает поле', (tester) async {
    await tester.pumpWidget(app(const ChatComposer(conversationId: 'conv-1')));
    await tester.enterText(find.byType(TextField), 'Ку 👋');
    await tester.pump();
    await tester.tap(find.byTooltip('Отправить'));
    await tester.pumpAndSettle();
    expect(repository.sent, ['Ку 👋']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('сообщение из одного эмодзи — без пузыря и крупно', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        MessageBubble(
          message: ChatMessage(
            id: 'm',
            conversationId: 'c',
            senderId: 'me',
            sentAt: DateTime(2026, 9, 30, 20, 18),
            text: '😁',
          ),
          mine: true,
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('😁'));
    expect(text.style!.fontSize, greaterThan(40));
  });

  group('меню сообщения', () {
    final peerMessage = ChatMessage(
      id: 'conv-1-0',
      conversationId: 'conv-1',
      senderId: 'person-1',
      sentAt: DateTime(2026, 9, 30),
      text: 'Привет!',
    );
    const direct = Conversation(
      id: 'conv-1',
      peerId: 'person-1',
      peerName: 'Алина',
      encrypted: false,
    );

    Future<ProviderContainer> openMenu(
      WidgetTester tester,
      ChatMessage message,
    ) async {
      await tester.pumpWidget(
        app(
          Consumer(
            builder: (context, ref, _) {
              return TextButton(
                onPressed: () => showMessageMenu(
                  context,
                  ref,
                  message: message,
                  myId: 'me',
                  conversation: direct,
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.text('open')));
    }

    testWidgets('у текста: копировать и удалить, удалить — красным и '
        'последним', (tester) async {
      await openMenu(tester, peerMessage);
      expect(find.text('Копировать'), findsOneWidget);
      expect(find.text('Сохранить в галерею'), findsNothing);
      final labels = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(labels.last, 'Удалить');
    });

    testWidgets('чужое в личном — скрывается у меня сразу, с отменой', (
      tester,
    ) async {
      final container = await openMenu(tester, peerMessage);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      // Диалога «удалить у всех» нет: чужое у собеседника не удалить.
      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(hiddenMessagesProvider), contains(peerMessage.id));

      await tester.tap(find.text('Отменить'));
      await tester.pump();
      expect(container.read(hiddenMessagesProvider), isEmpty);
    });

    testWidgets('своё — диалог с галочкой «и у собеседника», включённой', (
      tester,
    ) async {
      final mine = await repository.send(conversationId: 'conv-1', text: 'Ой');
      final container = await openMenu(tester, mine);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      expect(find.text('Удалить и у Алина'), findsOneWidget);
      final box = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box.value, isTrue);

      await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
      // Закрытие диалога и удаление занимают несколько кадров; pumpAndSettle
      // здесь не дожидался покоя, поэтому кадры отсчитываем явно.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byType(AlertDialog), findsNothing);
      // Поток заглушки живёт на настоящих микрозадачах, а не на фейковом
      // времени теста.
      final thread = await tester.runAsync(
        () => repository.watchMessages('conv-1').first,
      );
      expect(thread!.map((m) => m.id), isNot(contains(mine.id)));
      expect(container.read(hiddenMessagesProvider), contains(mine.id));
    });
  });

  test('компактная навигация — только внутри переписки', () {
    expect(HomeShell.isConversation('/chats/abc'), isTrue);
    expect(HomeShell.isConversation('/chats/abc/info'), isTrue);
    expect(HomeShell.isConversation('/chats'), isFalse);
    expect(HomeShell.isConversation('/chats/new-group'), isFalse);
    expect(HomeShell.isConversation('/feed'), isFalse);
  });
}
