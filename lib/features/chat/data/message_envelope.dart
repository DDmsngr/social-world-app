import 'dart:convert';

import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_meta.dart';

/// Конверт зашифрованного сообщения личного диалога.
///
/// Обычный текст без ответа и пересылки по-прежнему едет «голой» строкой —
/// так его читают и старые версии приложения. Всё остальное (вложения, текст
/// с ответом или пересылкой) — JSON с версией. Тип сообщения берётся из
/// конверта, а не из открытой колонки `kind`: её мог подменить сервер.
abstract final class MessageEnvelope {
  /// Метка текстового конверта: отличает «текст с ответом» от человека,
  /// который сам набрал что-то похожее на JSON.
  static const _textMarker = 'cw';

  static String encode({
    required MessageKind kind,
    String? text,
    ChatAttachment? attachment,
    ChatMeta meta = ChatMeta.empty,
  }) {
    if (kind == MessageKind.text && meta.isEmpty) return text ?? '';
    if (kind == MessageKind.text) {
      return jsonEncode({
        _textMarker: 1,
        'kind': kind.wire,
        'text': text ?? '',
        'm': meta.toJson(),
      });
    }
    return jsonEncode({
      'v': 1,
      'kind': kind.wire,
      'text': ?text,
      'a': ?attachment?.toJson(),
      if (!meta.isEmpty) 'm': meta.toJson(),
    });
  }

  static ({
    MessageKind kind,
    String text,
    ChatAttachment? attachment,
    ChatMeta meta,
  })
  decode(String clear, {required MessageKind rowKind}) {
    if (rowKind == MessageKind.text) {
      final envelope = clear.startsWith('{"$_textMarker":')
          ? _parse(clear)
          : null;
      if (envelope == null || envelope[_textMarker] != 1) {
        return (
          kind: MessageKind.text,
          text: clear,
          attachment: null,
          meta: ChatMeta.empty,
        );
      }
      return (
        kind: MessageKind.text,
        text: envelope['text'] as String? ?? '',
        attachment: null,
        meta: ChatMeta.fromJson(envelope['m']),
      );
    }

    final envelope = _parse(clear);
    if (envelope == null) {
      // Битый конверт вложения — показываем как есть, а не падаем.
      return (
        kind: MessageKind.text,
        text: clear,
        attachment: null,
        meta: ChatMeta.empty,
      );
    }
    return (
      kind: MessageKind.parse(envelope['kind']),
      text: envelope['text'] as String? ?? '',
      attachment: ChatAttachment.fromJson(envelope['a']),
      meta: ChatMeta.fromJson(envelope['m']),
    );
  }

  static Map<String, dynamic>? _parse(String source) {
    try {
      final value = jsonDecode(source);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
