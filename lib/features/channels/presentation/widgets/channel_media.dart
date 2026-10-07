import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/media/photo_viewer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/entities/chat_message.dart';
import '../../../chat/presentation/providers/chat_providers.dart';
import '../../../chat/presentation/widgets/attachment_views.dart';

/// Вложение поста канала. Фото показывается целиком, в своих пропорциях
/// (в разумных пределах 0.6–2.4); пока файл не пришёл, рамка 4:3. Пропорции
/// запоминаются, поэтому пост, который уже показывали, при прокрутке не
/// меняет высоту. Видео — рамка 16:9.
class ChannelMedia extends StatelessWidget {
  const ChannelMedia({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if ((message.attachment?.album.length ?? 0) > 0) return _Album(message: message);
    return switch (message.kind) {
      MessageKind.image => _ChannelPhoto(message: message),
      MessageKind.video => VideoPreview(message: message),
      _ => Padding(
        padding: const EdgeInsets.all(10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AttachmentView(message: message, mine: false),
        ),
      ),
    };
  }
}

/// Пост-альбом: несколько фото и видео сеткой, как в Telegram. Ряды: 2 → [2],
/// 3 → [1, 2], 4 → [2, 2], 6 → [3, 3] и т. д. Высота ряда подбирается по
/// пропорциям кадров: два вертикальных фото встают рядом целиком, а не
/// обрезаются до квадратов. Нажатие на фото открывает просмотр всех фото.
class _Album extends ConsumerStatefulWidget {
  const _Album({required this.message});

  final ChatMessage message;

  static const _gap = 2.0;

  /// Пропорции кадров (ширина/высота) по id файла альбома: при прокрутке
  /// назад пост сразу нужной высоты.
  static final _ratios = <String, double>{};

  /// Ширины ячеек и высота ряда: ряд заполняет ширину, кадры в своих
  /// пропорциях. Совсем высокий или низкий ряд ограничивается — тогда кадры
  /// слегка обрезаются.
  static ({List<double> widths, double height}) fitRow(List<double> ratios, double width) {
    final avail = width - _gap * (ratios.length - 1);
    final sum = ratios.fold<double>(0, (a, r) => a + r);
    final height = (avail / sum).clamp(width * 0.3, width * 1.1);
    return (widths: [for (final r in ratios) avail * r / sum], height: height);
  }

  @override
  ConsumerState<_Album> createState() => _AlbumState();
}

class _AlbumState extends ConsumerState<_Album> {
  ChatMessage get message => widget.message;
  static const _gap = _Album._gap;

  @override
  void initState() {
    super.initState();
    for (final item in _items()) {
      if (item.kind == MessageKind.image && !_Album._ratios.containsKey(item.id)) {
        _measure(item);
      }
    }
  }

  Future<void> _measure(ChatMessage item) async {
    try {
      final path = await ref.read(chatRepositoryProvider).attachmentFile(item);
      final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      _Album._ratios[item.id] = (descriptor.width / descriptor.height).clamp(0.5, 2.0);
      descriptor.dispose();
      buffer.dispose();
      if (mounted) setState(() {});
    } catch (_) {
      // Не узнали — ячейка останется квадратной.
    }
  }

  static List<int> rows(int n) => _rows(n);

  static List<int> _rows(int n) => switch (n) {
    1 => [1],
    2 => [2],
    3 => [1, 2],
    4 => [2, 2],
    5 => [2, 3],
    6 => [3, 3],
    7 => [2, 2, 3],
    8 => [2, 3, 3],
    9 => [3, 3, 3],
    _ => [3, 3, 4],
  };

  /// Каждый файл альбома — как отдельное сообщение: так работают и кэш
  /// файлов (по id сообщения), и готовые виджеты фото и видео.
  List<ChatMessage> _items() {
    final all = message.attachment!.all;
    return [
      for (var i = 0; i < all.length; i++)
        ChatMessage(
          id: i == 0 ? message.id : '${message.id}-a$i',
          conversationId: message.conversationId,
          senderId: message.senderId,
          sentAt: message.sentAt,
          kind: (all[i].mime ?? '').startsWith('video') ? MessageKind.video : MessageKind.image,
          attachment: all[i],
        ),
    ];
  }

  Future<void> _openPhotos(BuildContext context, List<ChatMessage> items, ChatMessage tapped) async {
    final photos = items.where((m) => m.kind == MessageKind.image).toList();
    final repo = ref.read(chatRepositoryProvider);
    try {
      final paths = await Future.wait(photos.map(repo.attachmentFile));
      if (!context.mounted) return;
      await showPhotoViewer(context, urls: paths, initialIndex: photos.indexOf(tapped));
    } catch (error) {
      AppLog.add('Альбом канала не открылся: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final layout = rows(items.length.clamp(1, 10));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var index = 0;
        final children = <Widget>[];
        for (var r = 0; r < layout.length; r++) {
          final rowItems = items.skip(index).take(layout[r]).toList();
          final k = rowItems.length;
          if (k == 0) break;
          // Пока пропорция неизвестна (или это видео): одиночный ряд —
          // широкая «обложка», в рядах — квадраты.
          final fit = _Album.fitRow([
            for (final item in rowItems) _Album._ratios[item.id] ?? (k == 1 ? 1 / 0.62 : 1.0),
          ], width);
          final cellH = fit.height;
          final cells = <Widget>[];
          for (var c = 0; c < k; c++, index++) {
            final item = rowItems[c];
            final cellW = fit.widths[c];
            cells.add(
              SizedBox(
                width: cellW,
                height: cellH,
                child: item.kind == MessageKind.video
                    ? VideoPreview(message: item, aspectRatio: cellW / cellH)
                    : _AlbumPhoto(
                        message: item,
                        onTap: () => _openPhotos(context, items, item),
                      ),
              ),
            );
            if (c < k - 1) cells.add(const SizedBox(width: _gap));
          }
          if (r > 0) children.add(const SizedBox(height: _gap));
          children.add(Row(children: cells));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}

class _AlbumPhoto extends ConsumerStatefulWidget {
  const _AlbumPhoto({required this.message, required this.onTap});

  final ChatMessage message;
  final VoidCallback onTap;

  @override
  ConsumerState<_AlbumPhoto> createState() => _AlbumPhotoState();
}

class _AlbumPhotoState extends ConsumerState<_AlbumPhoto> {
  late Future<String> _file = ref.read(chatRepositoryProvider).attachmentFile(widget.message);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return InkWell(
            onTap: () => setState(
              () => _file = ref.read(chatRepositoryProvider).attachmentFile(widget.message),
            ),
            child: ColoredBox(
              color: AppColors.card,
              child: Center(child: Icon(Icons.refresh, color: AppColors.textFaint)),
            ),
          );
        }
        final path = snapshot.data;
        if (path == null) return ColoredBox(color: AppColors.card);
        return GestureDetector(
          onTap: widget.onTap,
          child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 600, gaplessPlayback: true),
        );
      },
    );
  }
}

class _ChannelPhoto extends ConsumerStatefulWidget {
  const _ChannelPhoto({required this.message});

  final ChatMessage message;

  @override
  ConsumerState<_ChannelPhoto> createState() => _ChannelPhotoState();
}

class _ChannelPhotoState extends ConsumerState<_ChannelPhoto> {
  /// Пропорции уже показанных фото: при возврате к посту в прокрутке рамка
  /// сразу нужной высоты, и список не прыгает.
  static final _ratios = <String, double>{};

  late Future<({String path, double ratio})> _file = _fetch();

  Future<({String path, double ratio})> _fetch() async {
    final path = await ref.read(chatRepositoryProvider).attachmentFile(widget.message);
    var ratio = _ratios[widget.message.id];
    if (ratio == null) {
      try {
        final bytes = await File(path).readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        ratio = descriptor.width / descriptor.height;
        descriptor.dispose();
        buffer.dispose();
      } catch (_) {
        ratio = 4 / 3;
      }
      // Совсем узкие и совсем широкие кадры чуть обрезаются: иначе один
      // скриншот на всю высоту экрана съел бы ленту. Полный кадр — по тапу.
      ratio = ratio.clamp(0.6, 2.4);
      _ratios[widget.message.id] = ratio;
    }
    return (path: path, ratio: ratio);
  }

  @override
  void didUpdateWidget(_ChannelPhoto old) {
    super.didUpdateWidget(old);
    if (old.message.id != widget.message.id) _file = _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String path, double ratio})>(
      future: _file,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        return AspectRatio(
          // Пока файл не пришёл — 4:3; пришёл — фото целиком, в своих
          // пропорциях.
          aspectRatio: loaded?.ratio ?? _ratios[widget.message.id] ?? 4 / 3,
          child: _body(snapshot),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<({String path, double ratio})> snapshot) {
    if (snapshot.hasError) {
      AppLog.add('Фото канала не скачалось: ${snapshot.error}');
      return InkWell(
        onTap: () => setState(() => _file = _fetch()),
        child: ColoredBox(
          color: AppColors.card,
          child: Center(child: Icon(Icons.refresh, color: AppColors.textFaint)),
        ),
      );
    }
    final loaded = snapshot.data;
    if (loaded == null) return ColoredBox(color: AppColors.card);
    return GestureDetector(
      onTap: () => showPhotoViewer(context, urls: [loaded.path]),
      child: Image.file(
        File(loaded.path),
        fit: BoxFit.cover,
        // Лента не должна декодировать полноразмерный кадр ради превью.
        cacheWidth: 900,
        gaplessPlayback: true,
      ),
    );
  }
}
