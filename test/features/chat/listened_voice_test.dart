import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/chat/presentation/widgets/attachment_views.dart';

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(listenedVoiceProvider);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return container;
}

void main() {
  test('новое чужое голосовое — непрослушано, после тапа по play — прослушано', () async {
    final container = await _container({});
    final voice = container.read(listenedVoiceProvider.notifier);
    final fresh = DateTime.now().add(const Duration(seconds: 5));

    expect(voice.isNew('m1', fresh), isTrue);
    voice.mark('m1');
    expect(voice.isNew('m1', fresh), isFalse);
    expect(voice.isNew('m2', fresh), isTrue, reason: 'другое сообщение не затронуто');
  });

  test('всё, что пришло до первого запуска возможности, считается прослушанным', () async {
    final container = await _container({});
    final voice = container.read(listenedVoiceProvider.notifier);
    final old = DateTime.now().subtract(const Duration(days: 3));

    expect(voice.isNew('old', old), isFalse);
    expect(voice.isNew('nodate', null), isFalse);
  });

  test('прослушанное помнится между запусками', () async {
    final first = await _container({});
    first.read(listenedVoiceProvider.notifier).mark('m1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();

    final second = await _container({
      'chat_voice_listened': prefs.getStringList('chat_voice_listened') ?? [],
      'chat_voice_listened_since': prefs.getString('chat_voice_listened_since') ?? '',
    });
    final fresh = DateTime.now().add(const Duration(seconds: 5));
    expect(second.read(listenedVoiceProvider.notifier).isNew('m1', fresh), isFalse);
  });
}
