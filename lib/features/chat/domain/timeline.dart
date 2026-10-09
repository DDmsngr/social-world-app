import '../../calls/call_log.dart';
import 'entities/chat_message.dart';

/// Элемент ленты переписки: сообщение или звонок.
typedef TimelineEntry = ({DateTime at, ChatMessage? message, CallLogEntry? call});

/// Сообщения (от старых к новым) и звонки в одну ленту по времени. Слиянием,
/// а не сортировкой: порядок сообщений с одинаковым временем не меняется.
List<TimelineEntry> mergeCallsIntoTimeline(List<ChatMessage> messages, List<CallLogEntry> calls) {
  final sortedCalls = [...calls]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final result = <TimelineEntry>[];
  var c = 0;
  for (final m in messages) {
    while (c < sortedCalls.length && sortedCalls[c].createdAt.isBefore(m.sentAt)) {
      result.add((at: sortedCalls[c].createdAt, message: null, call: sortedCalls[c]));
      c++;
    }
    result.add((at: m.sentAt, message: m, call: null));
  }
  for (; c < sortedCalls.length; c++) {
    result.add((at: sortedCalls[c].createdAt, message: null, call: sortedCalls[c]));
  }
  return result;
}
