import 'dart:async';

typedef FeedRows = List<Map<String, dynamic>>;

/// Живая лента строк, которая переживает потерю связи.
///
/// Реалтайм Supabase может молча отвалиться (телефон уснул, сменилась сеть,
/// включили или выключили VPN): ошибки нет, просто новых сообщений нет, а
/// переписка выглядит «зависшей», пока человек не выйдет и не зайдёт снова.
/// Поэтому лента:
///  * переподключает реалтайм с нарастающей паузой, если он упал или закрылся;
///  * независимо от него обычным запросом раз в [pollEvery] подбирает то, что
///    реалтайм пропустил, — первый раз через [firstPoll], если он молчит;
///  * не выдаёт одно и то же дважды ([signature]) и склеивает пачки, пришедшие
///    пока шла расшифровка, — в итоге берётся самая свежая;
///  * после сбоя (например, нет ключей собеседника) пробует открыть контекст
///    снова на следующем проходе, а не залипает на ошибке.
///
/// Ошибки уходят в поток, но поток не закрывается: когда связь вернётся,
/// экран получит данные и сам вернётся к нормальному виду.
Stream<List<T>> liveFeed<C, T>({
  required Future<C> Function() openContext,
  required Stream<FeedRows> Function() subscribe,
  required Future<FeedRows> Function(C context) fetch,
  required Future<List<T>> Function(FeedRows rows, C context) decode,
  required String Function(FeedRows rows, C context) signature,
  Duration firstPoll = const Duration(seconds: 6),
  Duration pollEvery = const Duration(seconds: 15),
  Duration Function(int failures)? backoff,
  void Function(String message)? log,
}) {
  late final StreamController<List<T>> controller;
  StreamSubscription<FeedRows>? realtime;
  Timer? firstPollTimer;
  Timer? pollTimer;
  Timer? resubscribeTimer;
  Future<C>? contextFuture;
  String? lastSignature;
  FeedRows? waiting;
  var decoding = false;
  var failures = 0;
  var closed = false;

  Duration pause(int n) =>
      backoff?.call(n) ?? Duration(seconds: (2 << n.clamp(0, 4)).clamp(2, 30));

  Future<C> context() {
    final existing = contextFuture;
    if (existing != null) return existing;
    final future = openContext();
    contextFuture = future;
    // Неудачный контекст не кэшируем: следующая попытка начнёт заново.
    future.then(
      (_) {},
      onError: (Object _) {
        if (identical(contextFuture, future)) contextFuture = null;
      },
    );
    return future;
  }

  Future<void> deliver(FeedRows rows) async {
    if (closed) return;
    if (decoding) {
      waiting = rows;
      return;
    }
    decoding = true;
    try {
      var batch = rows;
      while (true) {
        final ctx = await context();
        final sig = signature(batch, ctx);
        if (sig != lastSignature) {
          lastSignature = sig;
          final items = await decode(batch, ctx);
          if (!closed) controller.add(items);
        }
        final next = waiting;
        waiting = null;
        if (next == null) break;
        batch = next;
      }
    } catch (error, stack) {
      // Следующая такая же пачка должна дойти до экрана, а не отсечься
      // по подписи.
      lastSignature = null;
      waiting = null;
      if (!closed) controller.addError(error, stack);
    } finally {
      decoding = false;
    }
  }

  Future<void> pollOnce() async {
    if (closed || decoding) return;
    try {
      final ctx = await context();
      await deliver(await fetch(ctx));
    } catch (error) {
      log?.call('Опрос сообщений: $error');
    }
  }

  void connect() {
    realtime?.cancel();
    void retryLater() {
      if (closed) return;
      failures++;
      resubscribeTimer?.cancel();
      resubscribeTimer = Timer(pause(failures), connect);
    }

    realtime = subscribe().listen(
      (rows) {
        failures = 0;
        deliver(rows);
      },
      onError: (Object error) {
        log?.call('Реалтайм сообщений: $error');
        retryLater();
      },
      onDone: retryLater,
    );
  }

  controller = StreamController<List<T>>(
    onListen: () {
      // Если открыть переписку нельзя (нет ключей, нет сети), экран узнаёт
      // об этом сразу, а не после первого опроса.
      context().then(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!closed) controller.addError(error, stack);
        },
      );
      connect();
      firstPollTimer = Timer(firstPoll, () {
        pollOnce();
        pollTimer = Timer.periodic(pollEvery, (_) => pollOnce());
      });
    },
    onCancel: () {
      closed = true;
      firstPollTimer?.cancel();
      pollTimer?.cancel();
      resubscribeTimer?.cancel();
      return realtime?.cancel();
    },
  );
  return controller.stream;
}
