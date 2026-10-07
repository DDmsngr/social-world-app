import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/calls/call_log.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/timeline.dart';

ChatMessage _m(String id, int minute) =>
    ChatMessage(id: id, conversationId: 'c', senderId: 'a', sentAt: DateTime(2026, 10, 7, 17, minute));

CallLogEntry _c(String id, int minute) => CallLogEntry(
  id: id,
  callerId: 'a',
  video: false,
  status: 'missed',
  createdAt: DateTime(2026, 10, 7, 17, minute),
);

void main() {
  test('звонки встают между сообщениями по времени, порядок сообщений не меняется', () {
    final entries = mergeCallsIntoTimeline(
      [_m('m1', 10), _m('m2', 20), _m('m3', 20)],
      [_c('late', 30), _c('mid', 15), _c('early', 5)],
    );
    expect(
      [for (final e in entries) e.message?.id ?? e.call!.id],
      ['early', 'm1', 'mid', 'm2', 'm3', 'late'],
    );
  });

  test('без звонков лента — те же сообщения', () {
    final entries = mergeCallsIntoTimeline([_m('m1', 1)], const []);
    expect(entries.single.message!.id, 'm1');
  });
}
