import 'package:image_picker/image_picker.dart';

import '../../../../core/debug/app_log.dart';
import '../../../feed/domain/repositories/feed_repository.dart';

/// Выбор и загрузка фото для текста статьи: загружаются сразу, потому что в
/// Markdown нужна готовая ссылка. Фото, которое не загрузилось, пропускается
/// и уходит в [onError], остальные встают в статью.
Future<List<String>> pickArticleImages({
  required ImagePicker picker,
  required FeedRepository repository,
  required int limit,
  required void Function(Object error) onError,
}) async {
  final files = await picker.pickMultiImage(imageQuality: 85);
  final urls = <String>[];
  for (final file in files.take(limit)) {
    try {
      urls.add(await repository.uploadInlineImage(file.path));
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
}) async {
  final file = await picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(minutes: 1),
  );
  if (file == null) return null;
  try {
    return await repository.uploadInlineImage(file.path);
  } catch (error) {
    AppLog.add('Видео в текст не загрузилось: $error');
    onError(error);
    return null;
  }
}
