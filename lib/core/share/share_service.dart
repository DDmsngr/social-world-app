import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../links/deep_links.dart';

/// Системный лист «Поделиться» (iOS и Android) для объектов Social World.
///
/// В сообщение всегда кладётся ссылка именно на этот объект — не на приложение
/// вообще. Картинка-превью рисуется самой площадкой по метаданным страницы,
/// на которую ведёт ссылка (см. [DeepLinks.shareBase]); файлы приложение не
/// прикладывает, чтобы не качать картинку ради отправки текста.
abstract final class ShareService {
  static String message({
    required LinkTarget target,
    required String id,
    required String title,
    String? details,
    String city = 'Сочи',
  }) {
    final lines = [
      'ChaWo',
      '📍 $city',
      title.trim(),
      if (details != null && details.trim().isNotEmpty) details.trim(),
      '',
      DeepLinks.shareUri(target, id).toString(),
    ];
    return lines.join('\n');
  }

  static Future<void> share(
    BuildContext context, {
    required LinkTarget target,
    required String id,
    required String title,
    String? details,
  }) {
    // iPad требует, от какого места экрана раскрывать лист.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    return SharePlus.instance.share(
      ShareParams(
        text: message(target: target, id: id, title: title, details: details),
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
  }
}
