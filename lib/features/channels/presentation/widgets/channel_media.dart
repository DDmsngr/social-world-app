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
