/// Отличать видео от фотографии приходится по расширению в ссылке: отдельного
/// поля с типом у `posts.media_urls` нет, а заводить его ради одного бита
/// информации — значит чинить схему там, где имя файла и так всё говорит.
const _videoExtensions = {'.mp4', '.mov', '.m4v', '.webm'};

bool isVideoUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final dot = path.lastIndexOf('.');
  if (dot == -1) return false;
  return _videoExtensions.contains(path.substring(dot).toLowerCase());
}
