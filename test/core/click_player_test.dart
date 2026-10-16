import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/audio/click_player.dart';

void main() {
  test('проигрыватель освобождается, когда звук доиграл', () async {
    final done = StreamController<void>();
    var disposed = 0;
    final result = releaseWhenDone(done.stream, () => disposed++);
    done.add(null);
    await result;
    expect(disposed, 1);
  });

  test('закрытый поток без события не роняет и тоже освобождает', () async {
    final done = StreamController<void>();
    var disposed = 0;
    final result = releaseWhenDone(done.stream, () => disposed++);
    await done.close();
    await result;
    expect(disposed, 1);
  });

  test('зависший звук освобождается по таймауту без ошибки типа', () async {
    final done = StreamController<void>();
    var disposed = 0;
    await releaseWhenDone(
      done.stream,
      () => disposed++,
      timeout: const Duration(milliseconds: 20),
    );
    expect(disposed, 1);
  });
}
