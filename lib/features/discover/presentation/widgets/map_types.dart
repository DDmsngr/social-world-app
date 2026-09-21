/// Запрос «наведи камеру сюда». Сравнивается по ссылке: каждый вызов создаёт
/// новый объект, поэтому повторный выбор того же места всё равно двигает камеру.
class MapFocus {
  const MapFocus(this.latitude, this.longitude, {this.zoom = 16});

  final double latitude;
  final double longitude;
  final double zoom;
}
