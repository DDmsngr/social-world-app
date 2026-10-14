import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';

ChatAttachment _video(String path, int size, {int? ms = 8000, List<ChatAttachment> album = const []}) =>
    ChatAttachment(path: path, size: size, mime: 'video/mp4', durationMs: ms, album: album);

void main() {
  test('задвоенный ролик (разные адреса, тот же размер и длительность) — один файл', () {
    final twice = _video('a/1.mp4', 2100000, album: [_video('a/2.mp4', 2100000)]);
    expect(twice.all, hasLength(2));
    expect(twice.distinct.map((a) => a.path), ['a/1.mp4']);
  });

  test('разные ролики и фото остаются альбомом', () {
    final album = _video(
      'a/1.mp4',
      2100000,
      album: [
        _video('a/2.mp4', 1800000),
        const ChatAttachment(path: 'a/3.jpg', size: 2100000, mime: 'image/jpeg'),
      ],
    );
    expect(album.distinct, hasLength(3));
  });

  test('без альбома — само вложение', () {
    expect(_video('a/1.mp4', 5).distinct, hasLength(1));
  });
}
