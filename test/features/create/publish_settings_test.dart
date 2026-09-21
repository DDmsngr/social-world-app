import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/feed/data/local_feed_repository.dart';
import 'package:social_world/features/feed/domain/entities/post.dart';
import 'package:social_world/features/feed/domain/entities/publish_settings.dart';
import 'package:social_world/features/feed/presentation/providers/publish_settings_provider.dart';
import 'package:social_world/core/permissions/content_permissions.dart';

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(const AppUser(id: 'u1', displayName: 'Я')),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const friends = PublishSettings(visibility: PostVisibility.followers, showGeo: false);

  test('последние настройки и пресеты переживают перезапуск', () async {
    SharedPreferences.setMockInitialValues({});
    final first = _container();
    final ctl = first.read(publishSettingsProvider.notifier);
    ctl.update(friends);
    await ctl.savePreset('Друзья');
    await ctl.rememberAsDefault();

    // «Перезапуск»: новый контейнер, те же SharedPreferences.
    final second = _container();
    second.read(publishSettingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = second.read(publishSettingsProvider);
    expect(state.current, friends);
    expect(state.presets.single.name, 'Друзья');
    expect(state.activePreset?.name, 'Друзья');
  });

  test('чип пресета снимается, когда настройки тронули', () async {
    SharedPreferences.setMockInitialValues({});
    final c = _container();
    final ctl = c.read(publishSettingsProvider.notifier);
    ctl.update(friends);
    await ctl.savePreset('Друзья');
    ctl.update(friends.copyWith(showGeo: true));
    expect(c.read(publishSettingsProvider).activePreset, isNull);
  });

  test('чужой пост нельзя править и удалять', () async {
    var me = 'me';
    final repo = LocalFeedRepository(currentUserId: () => me, currentUserName: () => 'Я');
    final own = await repo.createPost(body: 'мой пост');
    me = 'stranger';
    await expectLater(
      repo.updatePost(own, body: 'взлом', settings: PublishSettings.defaults, keepMediaUrls: const []),
      throwsA(isA<PermissionDeniedException>()),
    );
    await expectLater(repo.deletePost(own.id), throwsA(isA<PermissionDeniedException>()));
    // «только мне» скрыт от чужих
    me = 'me';
    final secret = await repo.createPost(
      body: 'секрет',
      settings: const PublishSettings(visibility: PostVisibility.onlyMe),
    );
    me = 'stranger';
    expect((await repo.loadFeed()).any((p) => p.id == secret.id), isFalse);
  });
}