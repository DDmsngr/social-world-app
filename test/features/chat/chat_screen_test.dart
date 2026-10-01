import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';
import 'package:social_world/features/chat/presentation/chat_screen.dart';
import 'package:social_world/features/chat/presentation/providers/chat_providers.dart';
import 'package:social_world/features/chat/presentation/widgets/chat_composer.dart';
import 'package:social_world/features/chat/presentation/widgets/message_bubble.dart';
import 'package:social_world/features/chat/presentation/widgets/swipe_to_reply.dart';

class _SentCall {
  _SentCall(this.text, this.options);
  final String text;
  final SendOptions options;
}

/// Репозиторий, у которого поток сообщений управляется из теста: можно
/// «уронить» связь и посмотреть, что станет с экраном.
class _Repo extends LocalChatRepository {
  _Repo() : super(currentUserId: () => 'me');

  final streams = <StreamController<List<ChatMessage>>>[];
  final sent = <_SentCall>[];
  final scheduled = <({String text, DateTime? at, bool online, bool silent})>[];

  StreamController<List<ChatMessage>> get live => streams.last;

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    final controller = StreamController<List<ChatMessage>>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  }) async {
    sent.add(_SentCall(text, options));
    return ChatMessage(
      id: 'sent-${sent.length}',
      conversationId: conversationId,
      senderId: 'me',
      sentAt: DateTime.now(),
      text: text,
    );
  }

  @override
  Future<ScheduledMessage> scheduleText({
    required String conversationId,
    required String text,
    DateTime? sendAt,
    bool whenOnline = false,
    SendOptions options = SendOptions.none,
  }) {
    scheduled.add((
      text: text,
      at: sendAt,
      online: whenOnline,
      silent: options.silent,
    ));
    return super.scheduleText(
      conversationId: conversationId,
      text: text,
      sendAt: sendAt,
      whenOnline: whenOnline,
      options: options,
    );
  }
}

/// Лист или диалог выезжает за несколько кадров: первый кадр лишь запускает
/// анимацию, второй её проигрывает. Без этого кнопки ещё за краем экрана.
Future<void> _showUp(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

ChatMessage _msg(String id, String text, {String sender = 'person-1'}) =>
    ChatMessage(
      id: id,
      conversationId: 'conv-1',
      senderId: sender,
      sentAt: DateTime(2026, 10, 1, 9, 0),
      text: text,
    );

void main() {
  late _Repo repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _Repo();
  });
  tearDown(() async {
    for (final c in repo.streams) {
      await c.close();
    }
    repo.dispose();
  });

  Widget screen() => ProviderScope(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWithValue(
        const AppUser(id: 'me', displayName: 'Алексей'),
      ),
    ],
    child: const MaterialApp(
      home: ChatScreen(conversationId: 'conv-1', peerName: 'Алина'),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen());
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('связь с сервером', () {
    testWidgets('при потере связи сообщения остаются на экране, а не спиннер', (
      tester,
    ) async {
      await open(tester);
      repo.live.add([_msg('m1', 'Увидимся в семь')]);
      await tester.pump();
      expect(find.text('Увидимся в семь'), findsOneWidget);
      expect(find.textContaining('Подключаемся'), findsNothing);

      // Реалтайм упал — раньше тут появлялся спиннер вместо переписки.
      repo.live.addError(StateError('realtime отвалился'));
      await tester.pump();
      expect(find.text('Увидимся в семь'), findsOneWidget);
      expect(find.textContaining('Подключаемся'), findsOneWidget);

      // Даже когда провайдер перезапускает поток, сообщения не пропадают.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Увидимся в семь'), findsOneWidget);

      // Связь вернулась — полоска уходит, новое сообщение появилось.
      repo.live.add([_msg('m1', 'Увидимся в семь'), _msg('m2', 'Ок')]);
      await tester.pump();
      expect(find.text('Ок'), findsOneWidget);
      expect(find.textContaining('Подключаемся'), findsNothing);
    });

    testWidgets('первая загрузка дольше 10 секунд — кнопка «Переподключить»', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Переподключить'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
      expect(find.text('Долго подключаемся к чату'), findsOneWidget);

      final before = repo.streams.length;
      await tester.tap(find.text('Переподключить'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.streams.length, greaterThan(before),
          reason: 'нажатие заново открывает поток сообщений');
    });

    testWidgets('после разворота приложения чат переподключается сам', (
      tester,
    ) async {
      await open(tester);
      repo.live.add([_msg('m1', 'Привет')]);
      await tester.pump();
      final before = repo.streams.length;

      // Допустимый путь платформы: свернули и вернулись.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.streams.length, greaterThan(before));
      // Пока новый поток молчит, прежняя переписка на месте.
      expect(find.text('Привет'), findsOneWidget);
    });
  });

  group('ответ', () {
    testWidgets('свайп справа налево — строка ответа, отправка уносит цитату', (
      tester,
    ) async {
      await open(tester);
      repo.live.add([_msg('m1', 'Давай в семь')]);
      await tester.pump();

      await tester.drag(find.text('Давай в семь'), const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ответ: Алина'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Давай');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.sent, hasLength(1));
      final reply = repo.sent.single.options.replyTo!;
      expect(reply.messageId, 'm1');
      expect(reply.senderName, 'Алина');
      expect(reply.preview, 'Давай в семь');
      expect(find.text('Ответ: Алина'), findsNothing, reason: 'после отправки строка ответа уходит');
    });

    testWidgets('крестик отменяет ответ', (tester) async {
      await open(tester);
      repo.live.add([_msg('m1', 'Давай в семь')]);
      await tester.pump();
      await tester.drag(find.text('Давай в семь'), const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ответ: Алина'), findsOneWidget);

      await tester.tap(find.byTooltip('Отменить ответ'));
      await tester.pump();
      expect(find.text('Ответ: Алина'), findsNothing);
    });

    testWidgets('короткое движение пальцем ответа не начинает', (tester) async {
      await open(tester);
      repo.live.add([_msg('m1', 'Давай в семь')]);
      await tester.pump();
      await tester.drag(find.text('Давай в семь'), const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Ответ:'), findsNothing);
    });
  });

  group('отправка особым способом', () {
    Future<void> typeAndHold(WidgetTester tester) async {
      await open(tester);
      repo.live.add([_msg('m1', 'Привет')]);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Напомню завтра');
      await tester.pump();
      await tester.longPress(find.byIcon(Icons.send));
      await _showUp(tester);
    }

    testWidgets('долгий тап: без звука, потом, когда будет в сети', (
      tester,
    ) async {
      await typeAndHold(tester);
      expect(find.text('Отправить без звука'), findsOneWidget);
      expect(find.text('Отправить потом'), findsOneWidget);
      expect(find.text('Когда будет в сети'), findsOneWidget);
      // Обычный тап при этом ничего не отправил.
      expect(repo.sent, isEmpty);
    });

    testWidgets('«без звука» отправляет сообщение с флагом', (tester) async {
      await typeAndHold(tester);
      await tester.tap(find.text('Отправить без звука'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.sent.single.text, 'Напомню завтра');
      expect(repo.sent.single.options.silent, isTrue);
    });

    testWidgets('«когда будет в сети» откладывает и показывает «Запланировано»', (
      tester,
    ) async {
      await typeAndHold(tester);
      await tester.tap(find.text('Когда будет в сети'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(repo.sent, isEmpty);
      expect(repo.scheduled.single.online, isTrue);
      expect(repo.scheduled.single.at, isNull);
      expect(find.textContaining('появится в сети'), findsOneWidget);
      expect(find.text('Запланировано: 1'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: 'отложенное ушло из поля ввода',
      );
    });

    testWidgets('список запланированного: можно отменить отправку', (
      tester,
    ) async {
      await typeAndHold(tester);
      await tester.tap(find.text('Когда будет в сети'));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Запланировано: 1'));
      await _showUp(tester);
      expect(find.text('Напомню завтра'), findsOneWidget);
      expect(find.textContaining('появится в сети'), findsWidgets);

      await tester.tap(find.byTooltip('Отменить отправку'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(await repo.loadScheduled('conv-1'), isEmpty);
    });

    testWidgets('в группе «когда будет в сети» не предлагается', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(conversationId: 'conv-1', isDirect: false),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Всем привет');
      await tester.pump();
      await tester.longPress(find.byIcon(Icons.send));
      await _showUp(tester);
      expect(find.text('Отправить без звука'), findsOneWidget);
      expect(find.text('Отправить потом'), findsOneWidget);
      expect(find.text('Когда будет в сети'), findsNothing);
    });
  });

  group('пузырь', () {
    Future<void> show(WidgetTester tester, ChatMessage message, {bool mine = false}) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(body: MessageBubble(message: message, mine: mine)),
            ),
          ),
        );

    testWidgets('показывает цитату и «Переслано от»', (tester) async {
      await show(
        tester,
        ChatMessage(
          id: 'm',
          conversationId: 'c',
          senderId: 'p',
          sentAt: DateTime(2026, 10, 1, 9),
          text: 'Договорились',
          replyTo: const ChatReply(
            messageId: 'q',
            senderName: 'Марк',
            preview: 'Завтра в семь?',
          ),
          forwardedFrom: 'Лена',
        ),
      );
      expect(find.text('Договорились'), findsOneWidget);
      expect(find.text('Марк'), findsOneWidget);
      expect(find.text('Завтра в семь?'), findsOneWidget);
      expect(find.text('Переслано от Лена'), findsOneWidget);
    });

    testWidgets('одиночный эмодзи с ответом остаётся в пузыре с цитатой', (
      tester,
    ) async {
      await show(
        tester,
        ChatMessage(
          id: 'm',
          conversationId: 'c',
          senderId: 'p',
          sentAt: DateTime(2026, 10, 1, 9),
          text: '👍',
          replyTo: const ChatReply(messageId: 'q', senderName: 'Марк', preview: 'Идём?'),
        ),
      );
      expect(find.text('Идём?'), findsOneWidget);
      expect(tester.widget<Text>(find.text('👍')).style!.fontSize, lessThan(30));
    });
  });

  group('SwipeToReply', () {
    Future<int> swipe(WidgetTester tester, double dx, {bool enabled = true}) async {
      var replies = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeToReply(
              enabled: enabled,
              onReply: () => replies++,
              child: const SizedBox(width: 300, height: 60, child: Text('сообщение')),
            ),
          ),
        ),
      );
      await tester.drag(find.text('сообщение'), Offset(dx, 0));
      await tester.pump(const Duration(milliseconds: 300));
      return replies;
    }

    testWidgets('дальше порога — ответ один раз', (tester) async {
      expect(await swipe(tester, -120), 1);
    });

    testWidgets('не дотянули до порога — ответа нет', (tester) async {
      expect(await swipe(tester, -40), 0);
    });

    testWidgets('вправо сообщение не тянется и ответа нет', (tester) async {
      expect(await swipe(tester, 150), 0);
    });

    testWidgets('выключенный свайп ничего не делает', (tester) async {
      expect(await swipe(tester, -150, enabled: false), 0);
    });

    testWidgets('после жеста сообщение возвращается на место', (tester) async {
      await swipe(tester, -120);
      await tester.pump(const Duration(milliseconds: 500));
      final start = tester.getTopLeft(find.text('сообщение')).dx;
      expect(start, lessThan(400));
      expect(
        tester
            .widget<Transform>(
              find.descendant(
                of: find.byType(SwipeToReply),
                matching: find.byType(Transform),
              ).last,
            )
            .transform
            .getTranslation()
            .x,
        0,
      );
    });
  });
}
