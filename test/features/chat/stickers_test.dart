import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/data/message_envelope.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';
import 'package:social_world/features/chat/domain/stickers.dart';
import 'package:social_world/features/chat/presentation/providers/chat_providers.dart';
import 'package:social_world/features/chat/presentation/providers/sticker_providers.dart';
import 'package:social_world/features/chat/presentation/widgets/chat_composer.dart';
import 'package:social_world/features/chat/presentation/widgets/message_bubble.dart';

// Фирменные стикеры: каталог из ассетов, поиск по словам («любовь» находит
// все стикеры про любовь) и то, как стикер едет в сообщении — id в служебной
// части, эмодзи-заменитель в тексте для версий, которые стикеров не знают.
StickerCatalog _loadCatalog() => StickerCatalog.fromJson(
  jsonDecode(File('assets/stickers/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

class _SpyRepository extends LocalChatRepository {
  _SpyRepository() : super(currentUserId: () => 'me');

  final sent = <(String, MessageKind, SendOptions)>[];

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  }) {
    sent.add((text, kind, options));
    return super.send(
      conversationId: conversationId,
      text: text,
      kind: kind,
      options: options,
    );
  }
}

void main() {
  final catalog = _loadCatalog();
  List<String> ids(List<Sticker> stickers) => [for (final s in stickers) s.id];

  group('каталог', () {
    test('140 стикеров, id уникальны, у каждого есть картинка', () {
      final all = [for (final p in catalog.packs) ...p.stickers];
      expect(all, hasLength(140));
      expect(ids(all).toSet(), hasLength(140));
      for (final sticker in all) {
        expect(File(sticker.asset).existsSync(), isTrue, reason: sticker.id);
        expect(sticker.emoji, isNotEmpty, reason: sticker.id);
        expect(sticker.title, isNotEmpty, reason: sticker.id);
        expect(sticker.emotions, isNotEmpty, reason: sticker.id);
        for (final family in sticker.emotions) {
          expect(catalog.families, contains(family), reason: sticker.id);
        }
      }
    });

    test('путь к картинке только для id нашего вида', () {
      expect(stickerAsset('chao.wave'), 'assets/stickers/chao/wave.webp');
      expect(stickerAsset('../secret'), isNull);
      expect(stickerAsset('chao/../x.y'), isNull);
      expect(stickerAsset('Chao.Wave'), isNull);
      expect(stickerAsset(''), isNull);
      expect(stickerAsset(null), isNull);
    });
  });

  group('поиск', () {
    test('«любовь» находит все стикеры про любовь, главные — первыми', () {
      final found = ids(catalog.search('любовь'));
      const core = [
        'basic.heart',
        'basic.heart_eyes',
        'basic.kiss',
        'more.cat_heart_eyes',
        'city.hearts_orbit',
        'city.chat_heart',
        'chao.heart_eyes',
        'chao.kiss',
      ];
      expect(found.take(core.length).toSet(), core.toSet());
      // Побочная любовь — тоже в выдаче, но ниже.
      expect(found, containsAll(['more.hug', 'chao.hug', 'chao.coffee']));
      expect(
        found.indexOf('chao.coffee'),
        greaterThan(found.indexOf('basic.heart')),
      );
    });

    test('другие формы слова находят то же самое', () {
      for (final query in ['любви', 'люблю', 'Любовью', 'влюблён']) {
        expect(
          ids(catalog.search(query)),
          contains('basic.heart_eyes'),
          reason: query,
        );
      }
    });

    test('по эмодзи — стикеры с тем же заменителем', () {
      expect(
        ids(catalog.search('😍')),
        containsAll(['basic.heart_eyes', 'chao.heart_eyes']),
      );
      // «❤» без вариантного селектора — тот же эмодзи, что «❤️».
      expect(ids(catalog.search('❤')), contains('basic.heart'));
    });

    test('точное название — первым', () {
      expect(catalog.search('грусть').first.id, 'basic.sad');
      expect(ids(catalog.search('кофе')).take(2).toSet(), {
        'more.coffee',
        'chao.coffee',
      });
      expect(ids(catalog.search('ржу')), contains('basic.laugh_tears'));
    });

    test('короткие слова и пустой запрос ничего не подсказывают', () {
      for (final query in ['', '  ', 'да', 'ну', 'не', 'а', 'ок?', 'до']) {
        expect(catalog.search(query), isEmpty, reason: query);
      }
    });

    test('несколько слов — нужно совпадение по каждому', () {
      expect(catalog.search('грустный кофе'), isEmpty);
      expect(ids(catalog.search('люблю кофе')), contains('chao.coffee'));
    });
  });

  group('стикер в сообщении', () {
    test('id едет в служебной части, текст — эмодзи', () {
      const meta = ChatMeta(sticker: 'chao.wave');
      expect(ChatMeta.fromJson(meta.toJson()).sticker, 'chao.wave');
      expect(const SendOptions(sticker: 'chao.wave').meta.sticker, 'chao.wave');

      final encoded = MessageEnvelope.encode(
        kind: MessageKind.sticker,
        text: '👋',
        meta: meta,
      );
      final decoded = MessageEnvelope.decode(
        encoded,
        rowKind: MessageKind.sticker,
      );
      expect(decoded.kind, MessageKind.sticker);
      expect(decoded.text, '👋');
      expect(decoded.meta.sticker, 'chao.wave');
    });
  });

  group('экран', () {
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
        stickerCatalogProvider.overrideWith((ref) async => catalog),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

    ChatMessage sticker(String? id, String emoji) => ChatMessage(
      id: 'm',
      conversationId: 'c',
      senderId: 'me',
      sentAt: DateTime(2026, 10, 9, 12),
      kind: MessageKind.sticker,
      text: emoji,
      stickerId: id,
    );

    testWidgets('известный стикер — картинка без пузыря', (tester) async {
      await tester.pumpWidget(
        app(MessageBubble(message: sticker('chao.wave', '👋'), mine: true)),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
      expect(find.text('👋'), findsNothing);
    });

    testWidgets('незнакомый стикер — крупный эмодзи-заменитель', (
      tester,
    ) async {
      // Стикер из версии новее этой: картинки в ассетах нет, загрузка
      // падает — и на её месте эмодзи из текста.
      await tester.pumpWidget(
        app(MessageBubble(message: sticker('future.thing', '🦄'), mine: true)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('🦄')).style!.fontSize,
        greaterThan(40),
      );
    });

    testWidgets(
      'набрал «любовь» — полоса стикеров, нажатие отправляет стикер',
      (tester) async {
        await tester.pumpWidget(
          app(const ChatComposer(conversationId: 'conv-1')),
        );
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'любовь');
        await tester.pump();

        final first = catalog.search('любовь').first;
        final suggestion = find.byKey(
          ValueKey('sticker-suggestion-${first.id}'),
        );
        expect(suggestion, findsOneWidget);

        await tester.tap(suggestion);
        await tester.pumpAndSettle();
        expect(repository.sent, hasLength(1));
        final (text, kind, options) = repository.sent.single;
        expect(text, first.emoji);
        expect(kind, MessageKind.sticker);
        expect(options.sticker, first.id);
        // Набранное было запросом, а не сообщением — поле очищается.
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      },
    );

    testWidgets('обычное длинное сообщение стикеров не подсказывает', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const ChatComposer(conversationId: 'conv-1')),
      );
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'я тебя очень люблю и скучаю',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sticker-suggestion-basic.heart')),
        findsNothing,
      );
    });

    testWidgets('панель открывается на своих стикерах, их вкладки — первыми', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          const Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(conversationId: 'conv-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Эмодзи'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-basic.smile')), findsOneWidget);
      final lastPack = tester.getCenter(
        find.byKey(const ValueKey('sticker-pack-chao')),
      );
      final recent = tester.getCenter(find.byKey(const ValueKey('emoji-tab')));
      expect(lastPack.dx, lessThan(recent.dx));
    });

    testWidgets('паки стикеров — вкладками в панели эмодзи', (tester) async {
      await tester.pumpWidget(
        app(
          const Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(conversationId: 'conv-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Эмодзи'));
      await tester.pumpAndSettle();
      // Панель открывается в режиме эмодзи — переключаемся на стикеры.
      await tester.tap(find.byKey(const ValueKey('panel-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-pack-chao')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-chao.lookout')));
      await tester.pumpAndSettle();
      expect(repository.sent.single.$3.sticker, 'chao.lookout');
    });
  });

  group('свои эмодзи в тексте', () {
    final wave = catalog.byId('chao.wave')!;
    final heart = catalog.byId('basic.heart_eyes')!;

    test('черновик: символы-заместители становятся эмодзи и отметками', () {
      final draft =
          'Привет ${catalog.inlineChar(wave)}! ${catalog.inlineChar(heart)}';
      final (:text, :emoji) = catalog.encodeDraft(draft);
      expect(text, 'Привет 👋! 😍');
      expect(emoji, const [
        CustomEmoji(offset: 7, text: '👋', sticker: 'chao.wave'),
        CustomEmoji(offset: 11, text: '😍', sticker: 'basic.heart_eyes'),
      ]);
      // Каждый свой эмодзи — один символ: курсор и «стереть» как у буквы.
      expect(catalog.inlineChar(wave), hasLength(1));
      expect(
        catalog.byInlineCode(catalog.inlineChar(wave).codeUnitAt(0)),
        wave,
      );
      expect(catalog.byInlineCode('а'.codeUnitAt(0)), isNull);
    });

    test('отметки, не сходящиеся с текстом, отбрасываются', () {
      const ok = CustomEmoji(offset: 0, text: '👋', sticker: 'chao.wave');
      const shifted = CustomEmoji(offset: 1, text: '👋', sticker: 'chao.wave');
      const outside = CustomEmoji(
        offset: 40,
        text: '😍',
        sticker: 'basic.heart_eyes',
      );
      expect(validCustomEmoji('👋 ок', [shifted, ok, outside]), [ok]);
      // После правки текста в группе отметка съехала — остаётся обычный эмодзи.
      expect(validCustomEmoji('ок 👋', [ok]), isEmpty);
    });

    test('отметки едут в служебной части, чужой мусор не проходит', () {
      const meta = ChatMeta(
        emoji: [CustomEmoji(offset: 3, text: '👋', sticker: 'chao.wave')],
      );
      final json = meta.toJson();
      expect(ChatMeta.fromJson(json).emoji, meta.emoji);
      expect(
        ChatMeta.fromJson({
          'e': [
            {'o': -1, 't': '👋', 's': 'chao.wave'},
            {'o': 0, 't': '👋', 's': '../x'},
            'мусор',
          ],
        }).emoji,
        isEmpty,
      );

      final encoded = MessageEnvelope.encode(
        kind: MessageKind.text,
        text: 'Ку 👋',
        meta: meta,
      );
      final decoded = MessageEnvelope.decode(
        encoded,
        rowKind: MessageKind.text,
      );
      expect(decoded.text, 'Ку 👋');
      expect(decoded.meta.emoji, meta.emoji);
    });
  });

  group('свои эмодзи на экране', () {
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
        stickerCatalogProvider.overrideWith((ref) async => catalog),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

    testWidgets('из панели смайл встаёт в текст картинкой и уходит эмодзи', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          const Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(conversationId: 'conv-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Привет');
      await tester.tap(find.byTooltip('Эмодзи'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-pack-chao')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-chao.wave')));
      await tester.pumpAndSettle();

      // Ничего не отправлено, в поле — картинка.
      expect(repository.sent, isEmpty);
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Клавиатура'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      final (text, kind, options) = repository.sent.single;
      expect(text, 'Привет👋');
      expect(kind, MessageKind.text);
      expect(options.customEmoji, const [
        CustomEmoji(offset: 6, text: '👋', sticker: 'chao.wave'),
      ]);
    });

    testWidgets('в пузыре свой эмодзи — картинкой среди текста', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          MessageBubble(
            message: ChatMessage(
              id: 'm',
              conversationId: 'c',
              senderId: 'me',
              sentAt: DateTime(2026, 10, 9, 12),
              text: 'Привет 👋 как дела',
              customEmoji: const [
                CustomEmoji(offset: 7, text: '👋', sticker: 'chao.wave'),
              ],
            ),
            mine: true,
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
    });
  });
}
