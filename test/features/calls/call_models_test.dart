import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/calls/call_models.dart';

void main() {
  group('пуш о звонке', () {
    test('разбирается в CallInfo и обратно', () {
      final info = CallInfo.fromPush({
        'type': 'call',
        'call_id': 'c1',
        'conversation_id': 'conv',
        'caller_id': 'u2',
        'caller_name': 'Аня',
        'caller_avatar': '',
        'video': '1',
      })!;
      expect(info.id, 'c1');
      expect(info.peerName, 'Аня');
      expect(info.peerAvatarUrl, isNull);
      expect(info.video, isTrue);
      expect(info.outgoing, isFalse);

      final again = CallInfo.fromPush(info.toPush())!;
      expect(again.id, info.id);
      expect(again.conversationId, info.conversationId);
      expect(again.peerId, info.peerId);
      expect(again.video, isTrue);
    });

    test('без обязательных полей — null, без имени — «ChaWo»', () {
      expect(CallInfo.fromPush({'call_id': 'c1'}), isNull);
      final info = CallInfo.fromPush({
        'call_id': 'c1',
        'conversation_id': 'conv',
        'caller_id': 'u2',
        'caller_name': '  ',
        'video': '0',
      })!;
      expect(info.peerName, 'ChaWo');
      expect(info.video, isFalse);
    });
  });

  group('итог звонка', () {
    test('глазами звонящего и получателя', () {
      expect(CallEndReason.fromStatus('busy', outgoing: true), CallEndReason.busy);
      expect(CallEndReason.fromStatus('missed', outgoing: true), CallEndReason.noAnswer);
      expect(CallEndReason.fromStatus('missed', outgoing: false), CallEndReason.cancelled);
      expect(CallEndReason.fromStatus('declined', outgoing: true), CallEndReason.declined);
      expect(CallEndReason.fromStatus('ended', outgoing: false), CallEndReason.hangUp);
    });

    test('подписи на экране', () {
      expect(callPhaseLabel(CallPhase.dialing, video: false), 'Вызов…');
      expect(callPhaseLabel(CallPhase.dialing, video: true), 'Видеозвонок…');
      expect(
        callPhaseLabel(CallPhase.active, video: false, talked: const Duration(minutes: 2, seconds: 5)),
        '2:05',
      );
      expect(
        callPhaseLabel(CallPhase.ended, video: false, reason: CallEndReason.busy),
        'Занято',
      );
    });

    test('длительность', () {
      expect(formatCallDuration(const Duration(seconds: 7)), '0:07');
      expect(formatCallDuration(const Duration(minutes: 12, seconds: 30)), '12:30');
      expect(formatCallDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });
}
