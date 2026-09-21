import '../entities/need_request.dart';

/// Договор с хранилищем «Мне надо». Отдельно от постов и событий: у просьбы
/// свой жизненный цикл — открыта, пока актуальна, и закрывается автором.
abstract interface class NeedsRepository {
  /// Живые просьбы вокруг точки — для Pulse и для «Рядом».
  Future<List<NeedRequest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
  });

  Future<NeedRequest?> loadNeed(String needId);

  Future<NeedRequest> createNeed({
    required String text,
    String? placeId,
    String? placeTitle,
    DateTime? expiresAt,
  });

  /// Автор закрывает просьбу: вопрос решён, с карты она уходит.
  Future<void> closeNeed(String needId);

  Future<void> deleteNeed(String needId);

  /// Мои просьбы, включая закрытые, — для профиля.
  Future<List<NeedRequest>> myNeeds();
}
