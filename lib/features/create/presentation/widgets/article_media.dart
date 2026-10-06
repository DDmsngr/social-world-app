import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/media/file_too_large.dart';
import '../../../feed/domain/repositories/feed_repository.dart';

/// Подпись к полосе загрузки и доля готового (0–1).
typedef UploadProgress = void Function(String label, double fraction);

/// Выбор и загрузка фото для текста статьи: загружаются сразу, потому что в
/// Markdown нужна готовая ссылка. Фото, которое не загрузилось, пропускается
/// и уходит в [onError], остальные встают в статью.
Future<List<String>> pickArticleImages({
  required ImagePicker picker,
  required FeedRepository repository,
  required int limit,
  required void Function(Object error) onError,
  required UploadProgress onProgress,
}) async {
  final files = (await picker.pickMultiImage(imageQuality: 85)).take(limit).toList();
  final urls = <String>[];
  for (var i = 0; i < files.length; i++) {
    final label = files.length == 1 ? 'Загружаем фото' : 'Загружаем фото ${i + 1} из ${files.length}';
    onProgress(label, i / files.length);
    try {
      urls.add(
        await repository.uploadInlineImage(
          files[i].path,
          onProgress: (p) => onProgress(label, (i + p) / files.length),
        ),
      );
    } catch (error) {
      AppLog.add('Фото в текст не загрузилось: $error');
      onError(error);
    }
  }
  return urls;
}

/// Видео в статье: до минуты, как вложение.
Future<String?> pickArticleVideo({
  required ImagePicker picker,
  required FeedRepository repository,
  required void Function(Object error) onError,
  required UploadProgress onProgress,
}) async {
  final file = await picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(minutes: 1),
  );
  if (file == null) return null;
  try {
    final size = await File(file.path).length();
    if (size > maxUploadBytes) throw FileTooLargeException(size);
    onProgress('Загружаем видео', 0);
    return await repository.uploadInlineImage(
      file.path,
      onProgress: (p) => onProgress('Загружаем видео', p),
    );
  } catch (error) {
    AppLog.add('Видео в текст не загрузилось: $error');
    onError(error);
    return null;
  }
}
