import '../entities/need_request.dart';

/// Договор с хранилищем «Мне надо». Отдельно от постов и событий: у просьбы
/// свой жизненный цикл — открыта, пока актуальна, и закрывается автором.
abstract interface class NeedsRepository {
  /// Живые просьбы вокруг точки — для Pulse и для «Рядом». Точка чужой
  /// просьбы приходит размытой (миграция 0023, `need_point`).
  Future<List<NeedRequest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
  });

  Future<NeedRequest?> loadNeed(String needId);

  /// Возвращает id новой просьбы. Место — либо [placeId], либо точка
  /// [latitude]/[longitude] с подписью [placeTitle]. Без [expiresAt] сервер
  /// ставит неделю.
  Future<String> createNeed({
    required String text,
    String? placeId,
    String? placeTitle,
    double? latitude,
    double? longitude,
    DateTime? expiresAt,
  });

  /// Автор закрывает просьбу: вопрос решён, с карты она уходит.
  Future<void> closeNeed(String needId);

  Future<void> deleteNeed(String needId);

  /// Мои просьбы, включая закрытые, — для профиля.
  Future<List<NeedRequest>> myNeeds();

  /// «Могу помочь». Отклик публичный, как комментарий: личной переписки в
  /// продукте пока нет. Повторный вызов обновляет текст.
  Future<void> respond(String needId, {String? text});

  Future<void> withdrawResponse(String needId);

  Future<List<NeedResponse>> loadResponses(String needId);
}
