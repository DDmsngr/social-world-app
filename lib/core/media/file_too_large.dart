/// Хранилище не принимает файлы тяжелее 50 МБ (выше отвечает 413), поэтому
/// проверяем заранее и объясняем человеку, а не показываем общую ошибку.
/// Берём с запасом: 49 МБ.
const maxUploadBytes = 49 * 1024 * 1024;

class FileTooLargeException implements Exception {
  const FileTooLargeException(this.bytes);

  final int bytes;

  String get message =>
      'Файл ${(bytes / (1024 * 1024)).round()} МБ — больше предела в '
      '${maxUploadBytes ~/ (1024 * 1024)} МБ. Выберите ролик покороче '
      'или поменьше качеством';

  @override
  String toString() => 'FileTooLargeException($bytes)';
}
