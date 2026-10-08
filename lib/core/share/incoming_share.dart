import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/app_log.dart';

/// Файл, присланный из другого приложения через «Поделиться»: уже лежит в
/// кэше ChaWo (MainActivity копирует его сразу).
class SharedFile {
  const SharedFile({required this.path, required this.name, this.mime, this.size = 0});

  final String path;
  final String name;
  final String? mime;
  final int size;

  bool get isImage => (mime ?? '').startsWith('image/');
  bool get isVideo => (mime ?? '').startsWith('video/');
}

/// Что прислало другое приложение: текст или ссылка и/или файлы.
class IncomingShare {
  const IncomingShare({this.text, this.files = const [], this.skipped = 0});

  final String? text;
  final List<SharedFile> files;

  /// Сколько файлов не взяли (слишком большие или не прочитались).
  final int skipped;

  bool get isEmpty => (text == null || text!.trim().isEmpty) && files.isEmpty;

  /// Разбор того, что пришло из нативной части. Мусор и пустое — null.
  static IncomingShare? parse(Object? raw) {
    if (raw is! Map) return null;
    final files = <SharedFile>[];
    final rawFiles = raw['files'];
    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is! Map) continue;
        final path = item['path'];
        if (path is! String || path.isEmpty) continue;
        files.add(
          SharedFile(
            path: path,
            name: (item['name'] as String?) ?? path.split(RegExp(r'[\\/]')).last,
            mime: item['mime'] as String?,
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    final text = raw['text'];
    final share = IncomingShare(
      text: text is String && text.trim().isNotEmpty ? text.trim() : null,
      files: files,
      skipped: (raw['skipped'] as num?)?.toInt() ?? 0,
    );
    return share.isEmpty && share.skipped == 0 ? null : share;
  }
}

/// Присланное из других приложений, ещё не разобранное экраном. Экран
/// (HomeShell) показывает выбор чата и сбрасывает состояние.
class IncomingShareController extends Notifier<IncomingShare?> {
  static const _channel = MethodChannel('chawo/share');

  var _started = false;

  @override
  IncomingShare? build() {
    ref.keepAlive();
    return null;
  }

  /// Подписка на присланное и разбор того, что пришло до запуска Dart
  /// (холодный старт по «Поделиться»). Вызывается один раз из оболочки.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') _accept(call.arguments);
      return null;
    });
    try {
      _accept(await _channel.invokeMethod<Object?>('initial'));
    } on MissingPluginException {
      // iOS и тесты: нативной части нет.
    } catch (error) {
      AppLog.add('Присланное из других приложений: $error');
    }
  }

  void _accept(Object? raw) {
    final share = IncomingShare.parse(raw);
    if (share != null) state = share;
  }

  void clear() => state = null;
}

final incomingShareProvider = NotifierProvider<IncomingShareController, IncomingShare?>(
  IncomingShareController.new,
);
