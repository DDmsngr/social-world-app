import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/core/router/app_router.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';
import 'package:social_world/features/chat/domain/stickers.dart';
import 'package:social_world/features/chat/presentation/providers/chat_providers.dart';
import 'package:social_world/features/chat/presentation/widgets/chat_composer.dart';
import 'package:social_world/features/chat/presentation/widgets/message_bubble.dart';
import 'package:social_world/features/stickers/presentation/my_stickers_screen.dart';
import 'package:social_world/features/stickers/presentation/sticker_pack_screen.dart';
import 'package:social_world/features/stickers/presentation/sticker_store_screen.dart';
import 'package:social_world/features/stickers/sticker_providers.dart';

import 'sticker_fixtures.dart';

// Магазин стикеров: каталог с сервера, коллекция пользователя, отправка из
// установленных паков, переход из сообщения к паку. Сервер — FakeStickerBackend
// (ведёт себя как база с RLS: без дублей, снятое с публикации не ставится).

/// Каталог как с сервера, где «Город» снят с публикации.
Map<String, dynamic> _catalogWithArchive() {
  final json = catalogJsonFromSources();
  for (final pack in json['packs'] as List) {
    if (pack['id'] == 'city') pack['status'] = 'archived';
  }
  return json;
}

class _SpyRepository extends LocalChatRepository {
  _SpyRepository() : super(currentUserId: () => 'me');

  final sent = <(String, MessageKind, SendOptions)>[];
  bool fail = false;

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  }) {
    if (fail) throw const SocketException('нет сети');
    sent.add((text, kind, options));
    return super.send(conversationId: conversationId, text: text, kind: kind, options: options);
  }
}

ProviderContainer _container(FakeStickerBackend backend, {String user = 'me'}) => ProviderContainer(
  overrides: [
    stickerBackendProvider.overrideWithValue(backend),
    currentUserProvider.overrideWithValue(AppUser(id: user)),
  ],
);

void main() {
  useTestStickerImages();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('модель каталога', () {
    final catalog = StickerCatalog.fromJson(_catalogWithArchive());

    test('пак: описание, издатель, категория, статус, обложка', () {
      final alexa = catalog.pack('alexa')!;
      expect(alexa.title, 'Алекса');
      expect(alexa.publisher, 'Команда ChaWo');
      expect(alexa.category, 'персонажи');
      expect(alexa.description, isNotEmpty);
      expect(alexa.isPublished, isTrue);
      expect(alexa.coverUrl, 'https://test/stickers/alexa/thumb/wave.webp');
      expect(catalog.pack('city')!.status, StickerPackStatus.archived);
      expect(catalog.categories, containsAll(['эмоции', 'персонажи']));
      // Категория снятого пака в фильтр магазина не попадает.
      expect(catalog.categories, isNot(contains('город')));
    });

    test('стикер: оригинал для переписки, превью для сеток', () {
      final cocoa = catalog.byId('alexa.cocoa')!;
      expect(cocoa.imageUrl, 'https://test/stickers/alexa/cocoa.webp');
      expect(cocoa.thumbUrl, 'https://test/stickers/alexa/thumb/cocoa.webp');
    });

    test('порядок стикеров — как в паке', () {
      final keys = [for (final s in catalog.pack('alexa')!.stickers) s.key];
      expect(keys.take(3), ['wave', 'laugh', 'smirk_think']);
    });

    test('поиск только по установленным пакам', () {
      expect(catalog.search('какао').map((s) => s.id), contains('alexa.cocoa'));
      expect(catalog.search('какао', packs: {'basic'}).map((s) => s.packId), everyElement('basic'));
      expect(catalog.search('какао', packs: {'basic'}).map((s) => s.id), isNot(contains('alexa.cocoa')));
    });
  });

  group('каталог и коллекция', () {
    test('каталог с сервера сохраняется и открывается без сети', () async {
      final online = FakeStickerBackend();
      final first = _container(online);
      final catalog = await first.read(stickerCatalogProvider.future);
      expect(catalog.packs.map((p) => p.id), containsAll(['basic', 'alexa']));
      first.dispose();

      final offline = FakeStickerBackend()..failCatalog = true;
      final second = _container(offline);
      final cached = await second.read(stickerCatalogProvider.future);
      expect(cached.packs.length, catalog.packs.length);
      await Future<void>.delayed(Duration.zero);
      // Фоновое обновление не прошло — каталог остался, ошибки на экране нет.
      expect(second.read(stickerCatalogProvider).hasError, isFalse);
      second.dispose();
    });

    test('без сети и без сохранённого — ошибка (экран покажет «Повторить»)', () async {
      final container = _container(FakeStickerBackend()..failCatalog = true);
      await expectLater(container.read(stickerCatalogProvider.future), throwsA(isA<SocketException>()));
      container.dispose();
    });

    test('установка без дублей, удаление, порядок вкладок', () async {
      final backend = FakeStickerBackend(installed: ['basic']);
      final container = _container(backend);
      await container.read(stickerCatalogProvider.future);
      await container.read(installedStickerPacksProvider.future);
      final installed = container.read(installedStickerPacksProvider.notifier);

      await installed.install('alexa');
      await installed.install('alexa');
      expect(backend.installedIds, ['basic', 'alexa']);
      expect(container.read(installedStickerPacksProvider).value, ['basic', 'alexa']);
      expect(container.read(myStickerPacksProvider).map((p) => p.id), ['basic', 'alexa']);

      await installed.uninstall('basic');
      expect(backend.installedIds, ['alexa']);
      expect(container.read(myStickerPacksProvider).map((p) => p.id), ['alexa']);
      // Каталог пак не теряет.
      expect(container.read(stickerCatalogProvider).value!.pack('basic'), isNotNull);
      container.dispose();
    });

    test('сервер не принял — откат и ошибка наружу', () async {
      final backend = FakeStickerBackend(installed: ['basic'])..failWrites = true;
      final container = _container(backend);
      await container.read(installedStickerPacksProvider.future);
      final installed = container.read(installedStickerPacksProvider.notifier);

      await expectLater(installed.install('alexa'), throwsA(isA<SocketException>()));
      expect(container.read(installedStickerPacksProvider).value, ['basic']);
      await expectLater(installed.uninstall('basic'), throwsA(isA<SocketException>()));
      expect(container.read(installedStickerPacksProvider).value, ['basic']);
      container.dispose();
    });

    test('снятый с публикации пак не ставится', () async {
      final backend = FakeStickerBackend(catalog: _catalogWithArchive());
      final container = _container(backend);
      await container.read(installedStickerPacksProvider.future);
      await expectLater(
        container.read(installedStickerPacksProvider.notifier).install('city'),
        throwsA(isA<StateError>()),
      );
      expect(container.read(installedStickerPacksProvider).value, isEmpty);
      container.dispose();
    });

    test('коллекция у каждого своя: сохранённая копия не переходит к другому', () async {
      final a = _container(FakeStickerBackend(installed: ['alexa']), user: 'a');
      expect(await a.read(installedStickerPacksProvider.future), ['alexa']);
      a.dispose();
      final b = _container(FakeStickerBackend(installed: ['basic'])..failCatalog = true, user: 'b');
      // Сервер недоступен, а копии у b нет — ошибка, не чужие паки.
      await expectLater(b.read(installedStickerPacksProvider.future), throwsA(isA<SocketException>()));
      b.dispose();
    });
  });

  group('экраны магазина', () {
    late FakeStickerBackend backend;

    Widget app(Widget home) => ProviderScope(
      overrides: [
        stickerBackendProvider.overrideWithValue(backend),
        currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
      ],
      child: MaterialApp(home: home),
    );

    setUp(() => backend = FakeStickerBackend(catalog: _catalogWithArchive(), installed: ['basic']));

    testWidgets('магазин: опубликованные паки, установка, «Установлен»', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(app(const StickerStoreScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pack-card-alexa')), findsOneWidget);
      // Снятый с публикации в магазине не показывается.
      expect(find.byKey(const ValueKey('pack-card-city')), findsNothing);
      expect(find.byKey(const ValueKey('pack-installed-basic')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pack-install-alexa')));
      await tester.pumpAndSettle();
      expect(backend.installedIds, ['basic', 'alexa']);
      // Кнопки больше нет — повторно не поставить.
      expect(find.byKey(const ValueKey('pack-install-alexa')), findsNothing);
      expect(find.byKey(const ValueKey('pack-installed-alexa')), findsOneWidget);
    });

    testWidgets('магазин: поиск по названию и категории', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(app(const StickerStoreScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('sticker-store-search')), 'алек');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pack-card-alexa')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-card-basic')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('sticker-store-search')), 'персонажи');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pack-card-chao')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-card-alexa')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-card-more')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('sticker-store-search')), 'нет такого');
      await tester.pumpAndSettle();
      expect(find.text('Ничего не нашлось'), findsOneWidget);
    });

    testWidgets('магазин без сети: ошибка и «Повторить»', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      addTearDown(tester.view.resetPhysicalSize);
      backend.failCatalog = true;
      await tester.pumpWidget(app(const StickerStoreScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Магазин не загрузился'), findsOneWidget);

      backend.failCatalog = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pack-card-alexa')), findsOneWidget);
    });

    testWidgets('пак по стикеру из переписки: стикер сверху и подсвечен, пак ставится', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(app(const StickerPackScreen(packId: 'alexa', highlight: 'cocoa')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sticker-highlight-banner')), findsOneWidget);
      expect(find.text('Стикер «какао»'), findsOneWidget);
      expect(find.bySemanticsLabel('Стикер «какао», выделен'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pack-install-alexa')));
      await tester.pumpAndSettle();
      expect(backend.installedIds, contains('alexa'));
      expect(find.text('Пак «Алекса» в ваших стикерах'), findsOneWidget);
    });

    testWidgets('снятый с публикации пак: виден, но не ставится', (tester) async {
      await tester.pumpWidget(app(const StickerPackScreen(packId: 'city', highlight: 'sunset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-highlight-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-install-city')), findsNothing);
      expect(find.text('Снят с публикации'), findsOneWidget);
    });

    testWidgets('мои стикеры: только установленные, убрать с подтверждением', (tester) async {
      backend = FakeStickerBackend(installed: ['basic', 'alexa']);
      await tester.pumpWidget(app(const MyStickersScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pack-card-basic')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-card-alexa')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-card-chao')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('remove-pack-basic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-remove-pack')));
      await tester.pumpAndSettle();
      expect(backend.installedIds, ['alexa']);
      expect(find.byKey(const ValueKey('pack-card-basic')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('remove-pack-alexa')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-remove-pack')));
      await tester.pumpAndSettle();
      expect(find.text('Здесь будут ваши стикеры'), findsOneWidget);
    });
  });

  group('стикеры в переписке', () {
    late _SpyRepository repository;
    late FakeStickerBackend backend;

    setUp(() {
      repository = _SpyRepository();
      backend = FakeStickerBackend(installed: ['alexa']);
    });
    tearDown(() => repository.dispose());

    Widget app(Widget child) => ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
        stickerBackendProvider.overrideWithValue(backend),
      ],
      child: MaterialApp(
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
      ),
    );

    testWidgets('кнопка стикеров: только установленные паки, тап отправляет стикер', (tester) async {
      await tester.pumpWidget(app(const ChatComposer(conversationId: 'conv-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-stickers')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sticker-pack-alexa')), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-pack-basic')), findsNothing);
      // Режим стикеров: вкладки обычных эмодзи нет, есть путь в магазин.
      expect(find.byKey(const ValueKey('emoji-tab')), findsNothing);
      expect(find.byKey(const ValueKey('sticker-store-tab')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sticker-alexa.wave')));
      await tester.pumpAndSettle();
      final (text, kind, options) = repository.sent.single;
      expect(kind, MessageKind.sticker);
      expect(options.sticker, 'alexa.wave');
      expect(text, '👋');
    });

    testWidgets('убрал пак — его стикеров нет ни в панели, ни в подсказках', (tester) async {
      backend = FakeStickerBackend(installed: ['alexa', 'basic']);
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        app(Consumer(builder: (context, ref, _) {
          widgetRef = ref;
          return const ChatComposer(conversationId: 'conv-1');
        })),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'какао');
      await tester.pump();
      expect(find.byKey(const ValueKey('sticker-suggestion-alexa.cocoa')), findsOneWidget);

      await widgetRef.read(installedStickerPacksProvider.notifier).uninstall('alexa');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-suggestion-alexa.cocoa')), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-stickers')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-pack-alexa')), findsNothing);
      expect(find.byKey(const ValueKey('sticker-pack-basic')), findsOneWidget);
    });

    testWidgets('стикеров нет — панель зовёт в магазин', (tester) async {
      backend = FakeStickerBackend(installed: []);
      await tester.pumpWidget(app(const ChatComposer(conversationId: 'conv-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-stickers')));
      await tester.pumpAndSettle();
      expect(find.text('У вас пока нет стикеров'), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-store-empty')), findsOneWidget);
    });

    testWidgets('стикер не ушёл — ошибка под полем', (tester) async {
      repository.fail = true;
      await tester.pumpWidget(app(const ChatComposer(conversationId: 'conv-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-stickers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-alexa.wave')));
      await tester.pumpAndSettle();
      // Сеть упала — понятная причина под полем, стикер не «ушёл» молча.
      expect(find.text('Нет связи с сервером'), findsOneWidget);
      expect(repository.sent, isEmpty);
    });

    testWidgets('тап по стикеру в сообщении — его пак в магазине, стикер выделен', (tester) async {
      // У получателя пак не установлен.
      backend = FakeStickerBackend(installed: []);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: MessageBubble(
                mine: false,
                message: ChatMessage(
                  id: 'm',
                  conversationId: 'c',
                  senderId: 'peer',
                  sentAt: DateTime(2026, 10, 13),
                  kind: MessageKind.sticker,
                  text: '☕',
                  stickerId: 'alexa.cocoa',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/stickers/pack/:id',
            builder: (_, state) => StickerPackScreen(
              packId: state.pathParameters['id']!,
              highlight: state.uri.queryParameters['s'],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
            stickerBackendProvider.overrideWithValue(backend),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(Routes.stickerPack('alexa', sticker: 'cocoa'), '/stickers/pack/alexa?s=cocoa');

      await tester.tap(find.byKey(const ValueKey('message-sticker')));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPackScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-highlight-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-install-alexa')), findsOneWidget);
    });
  });
}
