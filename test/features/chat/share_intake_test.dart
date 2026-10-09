import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/share/incoming_share.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/presentation/share_intake.dart';

SharedFile _file(String name, String mime) =>
    SharedFile(path: '/cache/$name', name: name, mime: mime, size: 100);

void main() {
  late List<String> kept;
  late int counter;

  Future<List<ChatMessage>> build(IncomingShare share) => buildShareMessages(
    share,
    newId: () => 'm${counter++}',
    keep: (id, kind, file) async => kept.add('$id:${kind.name}:${file.name}'),
  );

  setUp(() {
    kept = [];
    counter = 0;
  });

  group('IncomingShare.parse', () {
    test('читает текст и файлы, мусор и пустое отбрасывает', () {
      final share = IncomingShare.parse({
        'text': '  Смотри ссылку  ',
        'files': [
          {'path': '/c/a.jpg', 'name': 'a.jpg', 'mime': 'image/jpeg', 'size': 5},
          {'name': 'без пути'},
          'не файл',
        ],
        'skipped': 1,
      })!;
      expect(share.text, 'Смотри ссылку');
      expect(share.files.single.path, '/c/a.jpg');
      expect(share.files.single.isImage, isTrue);
      expect(share.skipped, 1);

      expect(IncomingShare.parse(null), isNull);
      expect(IncomingShare.parse({'text': '   ', 'files': []}), isNull);
      expect(IncomingShare.parse('текст'), isNull);
    });
  });

  group('buildShareMessages', () {
    test('только текст — одно текстовое сообщение', () async {
      final result = await build(const IncomingShare(text: 'https://example.com'));
      expect(result.single.kind, MessageKind.text);
      expect(result.single.text, 'https://example.com');
      expect(kept, isEmpty);
    });

    test('одно фото с текстом — фото с подписью, файл положен в кэш', () async {
      final result = await build(
        IncomingShare(text: 'Закат', files: [_file('a.jpg', 'image/jpeg')]),
      );
      expect(result.single.kind, MessageKind.image);
      expect(result.single.text, 'Закат');
      expect(kept, ['m0:image:a.jpg']);
    });

    test('несколько фото — один альбом, остальные файлы под своими id', () async {
      final result = await build(
        IncomingShare(
          files: [_file('a.jpg', 'image/jpeg'), _file('b.png', 'image/png'), _file('c.jpg', 'image/jpeg')],
        ),
      );
      expect(result.length, 1);
      expect(result.single.attachment!.all.length, 3);
      expect(kept, ['m0:image:a.jpg', 'm0-a1:image:b.png', 'm0-a2:image:c.jpg']);
    });

    test('видео и файл — отдельные сообщения, подпись у первого медиа', () async {
      final result = await build(
        IncomingShare(
          text: 'Вот',
          files: [_file('v.mp4', 'video/mp4'), _file('doc.pdf', 'application/pdf')],
        ),
      );
      expect(result.map((m) => m.kind), [MessageKind.video, MessageKind.file]);
      expect(result.first.text, 'Вот');
      expect(result.last.text, isNull);
    });

    test('фото и файл вместе: фото первым, подпись у него', () async {
      final result = await build(
        IncomingShare(
          text: 'Альбом',
          files: [_file('doc.pdf', 'application/pdf'), _file('a.jpg', 'image/jpeg')],
        ),
      );
      expect(result.first.kind, MessageKind.image);
      expect(result.first.text, 'Альбом');
      expect(result.last.kind, MessageKind.file);
    });
  });
}
