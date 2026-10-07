import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/calls/call_log.dart';

CallLogEntry _call(String status, {DateTime? answered, DateTime? ended, bool video = false}) => CallLogEntry(
  id: 'c',
  callerId: 'me',
  video: video,
  status: status,
  createdAt: DateTime(2026, 10, 7, 17, 51),
  answeredAt: answered,
  endedAt: ended,
);

void main() {
  test('состоявшийся звонок показывает длительность', () {
    final c = _call('ended', answered: DateTime(2026, 10, 7, 17, 51, 10), ended: DateTime(2026, 10, 7, 17, 53, 41));
    expect(callLogStatus(c, mine: true), '2:31');
    expect(callLogTitle(c, mine: true), 'Исходящий звонок');
    expect(callLogTitle(_call('ended', video: true), mine: false), 'Входящий видеозвонок');
  });

  test('статусы несостоявшихся звонков с обеих сторон', () {
    expect(callLogStatus(_call('missed'), mine: true), 'Без ответа');
    expect(callLogStatus(_call('missed'), mine: false), 'Пропущенный');
    expect(callLogStatus(_call('declined'), mine: true), 'Отклонён');
    expect(callLogStatus(_call('declined'), mine: false), 'Вы отклонили');
    expect(callLogStatus(_call('cancelled'), mine: false), 'Пропущенный');
    expect(callLogStatus(_call('busy'), mine: true), 'Занято');
    expect(callLogStatus(_call('ringing'), mine: true), 'Вызов…');
  });

  test('строка из базы', () {
    final c = CallLogEntry.fromRow({
      'id': 'x',
      'caller_id': 'a',
      'video': true,
      'status': 'missed',
      'created_at': '2026-10-07 14:51:03.627808+00',
      'answered_at': null,
      'ended_at': '2026-10-07 14:51:49.375591+00',
    });
    expect(c.video, isTrue);
    expect(c.talked, isFalse);
    expect(c.endedAt, isNotNull);
  });
}
