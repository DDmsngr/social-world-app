import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/media/photo_viewer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/entities/chat_message.dart';
import '../../../chat/presentation/providers/chat_providers.dart';
import '../../../chat/presentation/widgets/attachment_views.dart';

/// Вложение поста канала. В ленте у фото и видео фиксированная рамка (фото —
/// 4:3, видео — 16:9, обрезка «cover»): размеры файла заранее неизвестны, и
/// если подгонять рамку под них после загрузки, каждый пост в прокрутке
/// «прыгал» бы по высоте, а список дёргался. Полный кадр — в просмотрщике.
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
  late Future<String> _file = _fetch();

  Future<String> _fetch() =>
      ref.read(chatRepositoryProvider).attachmentFile(widget.message);

  @override
  void didUpdateWidget(_ChannelPhoto old) {
    super.didUpdateWidget(old);
    if (old.message.id != widget.message.id) _file = _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: FutureBuilder<String>(
        future: _file,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            AppLog.add('Фото канала не скачалось: ${snapshot.error}');
            return InkWell(
              onTap: () => setState(() => _file = _fetch()),
              child: ColoredBox(
                color: AppColors.card,
                child: Center(
                  child: Icon(Icons.refresh, color: AppColors.textFaint),
                ),
              ),
            );
          }
          final path = snapshot.data;
          if (path == null) return ColoredBox(color: AppColors.card);
          return GestureDetector(
            onTap: () => showPhotoViewer(context, urls: [path]),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              // Лента не должна декодировать полноразмерный кадр ради
              // превью в 400 px шириной.
              cacheWidth: 900,
              gaplessPlayback: true,
            ),
          );
        },
      ),
    );
  }
}
