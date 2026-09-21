import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/router/app_router.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/domain/repositories/auth_repository.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/feed/domain/entities/post.dart';
import 'package:social_world/features/feed/presentation/providers/feed_providers.dart';

/// Стрим полностью под контролем теста — в отличие от LocalAuthRepository,
/// который всегда даёт один и тот же id, здесь можно по-настоящему сменить
/// пользователя, чтобы проверить сброс сессионного состояния.
class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  void emit(AppUser? user) {
    _current = user;
    _controller.add(user);
  }

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _current;

  @override
  Future<void> requestEmailCode(String email) async {}

  @override
  Future<AppUser> verifyEmailCode({
    required String email,
    required String code,
  }) async => _current!;

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<AppUser> completeProfile({required String displayName}) async =>
      _current!;

  @override
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? city,
    String? avatarLocalPath,
  }) async => _current!;

  @override
  Future<AppUser> updateLocationBlur(int meters) async => _current!;

  void dispose() => unawaited(_controller.close());
}

void main() {
  test(
    'смена подтверждённого UID сбрасывает ленту, обновление того же '
    'пользователя — нет',
    () async {
      final fakeAuth = _FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fakeAuth)],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);

      // routerProvider — именно там живёт resetSessionScopedProviders;
      // держим ленту "активно watched", как это делает настоящий FeedScreen,
      // иначе invalidate() отложит пересборку до следующего чтения.
      container.read(routerProvider);
      final feedSub = container.listen(feedProvider, (_, _) {});
      addTearDown(feedSub.close);

      const userA = AppUser(id: 'user-a', displayName: 'Алина');
      fakeAuth.emit(userA);
      await container.read(feedProvider.future);

      container
          .read(feedProvider.notifier)
          .prepend(
            Post(
              id: 'draft-a',
              authorId: 'user-a',
              authorName: 'Алина',
              kind: PostKind.text,
              createdAt: DateTime.now(),
            ),
          );
      expect(
        container.read(feedProvider).value?.any((p) => p.id == 'draft-a'),
        isTrue,
      );

      // Обновление профиля у ТОГО ЖЕ пользователя (тот же id) не должно
      // стирать ленту — это не смена сессии, а просто новое имя.
      fakeAuth.emit(userA.copyWith(displayName: 'Алина М.'));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(feedProvider).value?.any((p) => p.id == 'draft-a'),
        isTrue,
        reason: 'обновление профиля того же UID не должно сбрасывать ленту',
      );

      // А смена на другого человека — должна.
      const userB = AppUser(id: 'user-b', displayName: 'Борис');
      fakeAuth.emit(userB);
      await container.read(feedProvider.future);
      expect(
        container.read(feedProvider).value?.any((p) => p.id == 'draft-a'),
        isFalse,
        reason: 'черновик пользователя A не должен пережить смену на B',
      );
    },
  );
}
