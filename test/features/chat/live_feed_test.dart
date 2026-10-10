import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/live_feed.dart';

// Лента сообщений переживает потерю связи. Баг, из-за которого появился
// liveFeed: переписка вдруг «начинала загружаться» и зависала, пока человек
// не выйдет и не зайдёт снова, — реалтайм молча отваливался, а запасного
// пути не было.
void main() {
  const tick = Duration(milliseconds: 20);

  FeedRows rows(List<String> ids) => [
    for (final id in ids) {'id': id},
  ];

  /// Лента на быстрых таймерах с управляемыми реалтаймом и запросом.
  _Harness harness({
    Future<int> Function()? openContext,
    // По умолчанию опрос далеко: тесты реалтайма не должны его замечать.
    Duration firstPoll = const Duration(seconds: 5),
    Duration pollEvery = const Duration(seconds: 5),
  }) => _Harness(
    openContext: openContext,
    firstPoll: firstPoll,
    pollEvery: pollEvery,
  );

  Future<void> wait([int ticks = 3]) =>
      Future<void>.delayed(tick * ticks);

  test('отдаёт расшифрованное из реалтайма', () async {
    final h = harness();
    final seen = <List<String>>[];
    final sub = h.stream.listen(seen.add);
    await wait();
    h.emit(rows(['a', 'b']));
    await wait();
    expect(seen, [
      ['a', 'b'],
    ]);
    await sub.cancel();
  });

  test('одинаковые пачки не повторяются', () async {
    final h = harness();
    final seen = <List<String>>[];
    final sub = h.stream.listen(seen.add);
    await wait();
    h.emit(rows(['a']));
    await wait();
    h.emit(rows(['a']));
    await wait();
    h.emit(rows(['a', 'b']));
    await wait();
    expect(seen, [
      ['a'],
      ['a', 'b'],
    ]);
    await sub.cancel();
  });

  test('реалтайм упал — переподключается и лента продолжается', () async {
    final h = harness();
    final seen = <List<String>>[];
    final sub = h.stream.listen(seen.add, onError: (_) {});
    await wait();
    expect(h.subscribes, 1);

    h.realtime.addError(StateError('канал закрыт'));
    await wait(8);
    expect(h.subscribes, 2, reason: 'после ошибки подписка создаётся заново');

    h.emit(rows(['a']));
    await wait();
    expect(seen, [
      ['a'],
    ]);
    await sub.cancel();
  });

  test('реалтайм закрылся без ошибки — тоже переподключается', () async {
    final h = harness();
    final sub = h.stream.listen((_) {});
    await wait();
    await h.realtime.close();
    await wait(8);
    expect(h.subscribes, 2);
    await sub.cancel();
  });

  test('реалтайм молчит — запросом всё равно приходит новое', () async {
    final h = harness(
      firstPoll: const Duration(milliseconds: 40),
      pollEvery: const Duration(milliseconds: 40),
    );
    h.fetched = rows(['x', 'y']);
    final seen = <List<String>>[];
    final sub = h.stream.listen(seen.add);
    // Реалтайм ничего не присылает, но опрос подбирает сообщения.
    await wait(6);
    expect(seen.first, ['x', 'y']);

    h.fetched = rows(['x', 'y', 'z']);
    await wait(6);
    expect(seen.last, ['x', 'y', 'z']);
    expect(h.fetches, greaterThanOrEqualTo(2));
    await sub.cancel();
  });

  test('если открыть контекст нельзя — ошибка уходит сразу, потом лечится', () async {
    var attempts = 0;
    final h = harness(
      openContext: () async {
        attempts++;
        if (attempts == 1) throw StateError('нет ключей');
        return 1;
      },
      // Опрос заметно реже проверок: на загруженной машине CI таймеры
      // запаздывают, и с коротким интервалом повтор успевал сработать раньше
      // проверки «данных ещё нет».
      firstPoll: const Duration(milliseconds: 600),
      pollEvery: const Duration(milliseconds: 600),
    );
    h.fetched = rows(['a']);
    final errors = <Object>[];
    final seen = <List<String>>[];
    final sub = h.stream.listen(seen.add, onError: errors.add);

    for (var i = 0; i < 100 && errors.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(errors, isNotEmpty, reason: 'экран сразу узнаёт о проблеме');
    expect(seen, isEmpty);

    for (var i = 0; i < 300 && seen.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(attempts, greaterThanOrEqualTo(2), reason: 'следующий проход пробует снова');
    expect(seen.last, ['a'], reason: 'и поток не закрылся — данные пришли');
    await sub.cancel();
  });

  test('ошибка расшифровки не залипает: та же пачка потом доходит', () async {
    final h = harness();
    var fail = true;
    h.decodeHook = () {
      if (fail) {
        fail = false;
        throw StateError('временный сбой');
      }
    };
    final seen = <List<String>>[];
    final errors = <Object>[];
    final sub = h.stream.listen(seen.add, onError: errors.add);
    await wait();
    h.emit(rows(['a']));
    await wait();
    expect(errors, hasLength(1));
    h.emit(rows(['a']));
    await wait();
    expect(seen, [
      ['a'],
    ], reason: 'после сбоя та же пачка не отсекается подписью');
    await sub.cancel();
  });

  test('пока идёт расшифровка, приходят три пачки — берётся последняя', () async {
    final h = harness();
    final release = Completer<void>();
    h.decodeGate = release.future;
    final seen = <List<String>>[];
    final sub = h.stream.listen(seen.add);
    await wait();

    h.emit(rows(['a']));
    await wait();
    h.emit(rows(['a', 'b']));
    h.emit(rows(['a', 'b', 'c']));
    await wait();
    h.decodeGate = null;
    release.complete();
    await wait(4);

    expect(seen.last, ['a', 'b', 'c']);
    expect(seen.length, lessThanOrEqualTo(2), reason: 'промежуточная пачка пропущена');
    await sub.cancel();
  });

  test('после отмены таймеры и запросы прекращаются', () async {
    final h = harness(
      firstPoll: const Duration(milliseconds: 40),
      pollEvery: const Duration(milliseconds: 40),
    );
    h.fetched = rows(['a']);
    final sub = h.stream.listen((_) {});
    await wait(6);
    await sub.cancel();
    final fetches = h.fetches;
    final subscribes = h.subscribes;
    await wait(10);
    expect(h.fetches, fetches);
    expect(h.subscribes, subscribes);
    expect(h.realtime.hasListener, isFalse);
  });
}

class _Harness {
  _Harness({
    Future<int> Function()? openContext,
    required Duration firstPoll,
    required Duration pollEvery,
  }) {
    stream = liveFeed<int, String>(
      openContext: openContext ?? () async => 1,
      subscribe: () {
        subscribes++;
        realtime = StreamController<FeedRows>();
        return realtime.stream;
      },
      fetch: (_) async {
        fetches++;
        return fetched;
      },
      decode: (rows, _) async {
        decodeHook?.call();
        final gate = decodeGate;
        if (gate != null) await gate;
        return [for (final r in rows) r['id'] as String];
      },
      signature: (rows, _) => rows.map((r) => r['id']).join(','),
      firstPoll: firstPoll,
      pollEvery: pollEvery,
      backoff: (_) => const Duration(milliseconds: 30),
    );
  }

  late final Stream<List<String>> stream;
  late StreamController<FeedRows> realtime;

  /// Сервер прислал строки: и реалтайм, и последующий опрос видят одно и то же.
  void emit(FeedRows rows) {
    fetched = rows;
    realtime.add(rows);
  }

  var subscribes = 0;
  var fetches = 0;
  FeedRows fetched = const [];
  void Function()? decodeHook;
  Future<void>? decodeGate;
}
