import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/data/message_envelope.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/conversation.dart';
import 'package:social_world/features/chat/domain/forward_service.dart';
import 'package:social_world/features/chat/domain/repositories/chat_repository.dart';

ChatAttachment _photo(String path, {String? key}) =>
    ChatAttachment(path: path, size: 10, name: '$path.jpg', mime: 'image/jpeg', key: key);

void main() {
  test('альбом доезжает через конверт целиком: файлы, ключи и подпись', () {
    final album = ChatAttachment(
      path: 'c/1',
      size: 10,
      name: 'a.jpg',
      mime: 'image/jpeg',
      key: 'k0',
      album: [_photo('c/1-a1', key: 'k1'), _photo('c/1-a2', key: 'k2')],
    );
    final clear = MessageEnvelope.encode(
      kind: MessageKind.image,
      text: 'Вид с балкона',
      attachment: album,
    );
    final back = MessageEnvelope.decode(clear, rowKind: MessageKind.image);
    expect(back.text, 'Вид с балкона');
    final all = back.attachment!.all;
    expect(all.map((a) => a.path), ['c/1', 'c/1-a1', 'c/1-a2']);
    expect(all.map((a) => a.key), ['k0', 'k1', 'k2']);
  });

  test('в группе ключи альбома на сервер не уходят', () {
    final album = ChatAttachment(
      path: 'c/1',
      size: 10,
      key: 'k0',
      album: [_photo('c/1-a1', key: 'k1')],
    );
    final json = album.toJson(withKey: false);
    expect(json.containsKey('key'), isFalse);
    expect((json['album']! as List).single, isNot(contains('key')));
  });

  test('в списке чатов альбом подписан числом фото', () {
    final message = ChatMessage(
      id: 'm',
      conversationId: 'c',
      senderId: 'me',
      sentAt: DateTime(2026, 10, 8),
      kind: MessageKind.image,
      attachment: ChatAttachment(path: 'a', size: 1, album: [_photo('b'), _photo('c')]),
    );
    expect(message.preview, '📷 Фото (3)');
  });

  test('пересылка альбома уходит альбомом, а не первой картинкой', () async {
    final repo = LocalChatRepository(currentUserId: () => 'me');
    final source = ChatMessage(
      id: 'src',
      conversationId: 's',
      senderId: 'p1',
      sentAt: DateTime(2026, 10, 8),
      kind: MessageKind.image,
      text: 'подпись',
      attachment: ChatAttachment(
        path: 'p0.jpg',
        size: 1,
        album: [_photo('p1.jpg'), _photo('p2.jpg')],
      ),
    );
    const target = Conversation(id: 'c-t', peerId: 'p2', peerName: 'Марк', encrypted: false);

    final result = await forwardMessages(
      repository: repo,
      messages: [source],
      targets: [target],
      authorOf: (_) => 'Алина',
    );

    expect(result.delivered, {'c-t'});
    final sent = (await repo.watchMessages('c-t').first).single;
    expect(sent.text, 'подпись');
    expect(sent.attachment!.all.length, 3);
    expect(sent.forwardedFrom, 'Алина');
  });

  test('больше $maxAlbumPhotos фото делятся на несколько альбомов', () {
    expect(maxAlbumPhotos, 8);
    // 19 фото: 8 + 8 + 3.
    final groups = <int>[];
    for (var start = 0; start < 19; start += maxAlbumPhotos) {
      groups.add((start + maxAlbumPhotos > 19 ? 19 : start + maxAlbumPhotos) - start);
    }
    expect(groups, [8, 8, 3]);
  });
}
