import 'dart:math' as math;

import '../../../core/errors/rule_violation.dart';
import '../domain/entities/need_request.dart';
import '../domain/repositories/needs_repository.dart';

/// «Мне надо» в памяти, пока Supabase не поднят. Правила — как у функций
/// миграции 0023: неделя по умолчанию, откликаться на своё нельзя, закрытая
/// просьба с карты уходит.
class LocalNeedsRepository implements NeedsRepository {
  LocalNeedsRepository({
    required this.currentUserId,
    required this.currentUserName,
    DateTime Function()? clock,
    bool seed = true,
  }) : _now = clock ?? DateTime.now {
    if (seed) _seed();
  }

  final String Function() currentUserId;
  final String Function() currentUserName;
  final DateTime Function() _now;

  final _needs = <String, NeedRequest>{};
  final _responses = <String, List<NeedResponse>>{};
  var _nextId = 0;

  static const defaultLifetime = Duration(days: 7);

  NeedRequest _withCounts(NeedRequest need) {
    final list = _responses[need.id] ?? const <NeedResponse>[];
    return need.copyWith(
      replyCount: list.length,
      respondedByMe: list.any((r) => r.authorId == currentUserId()),
    );
  }

  @override
  Future<List<NeedRequest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
  }) async => [
    for (final need in _needs.values)
      if (need.status == NeedStatus.open &&
          !(need.expiresAt?.isBefore(_now()) ?? false) &&
          need.hasLocation &&
          _distance(latitude, longitude, need.latitude!, need.longitude!) <= radiusMeters)
        _withCounts(need),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<NeedRequest?> loadNeed(String needId) async {
    final need = _needs[needId];
    return need == null ? null : _withCounts(need);
  }

  @override
  Future<List<NeedRequest>> myNeeds() async => [
    for (final need in _needs.values)
      if (need.authorId == currentUserId()) _withCounts(need),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<String> createNeed({
    required String text,
    String? placeId,
    String? placeTitle,
    double? latitude,
    double? longitude,
    DateTime? expiresAt,
  }) async {
    if ((latitude == null) != (longitude == null)) {
      throw const RuleViolation('need_bad_point');
    }
    if (expiresAt != null && !expiresAt.isAfter(_now())) {
      throw const RuleViolation('need_expired');
    }
    final id = 'local-need-${_nextId++}';
    _needs[id] = NeedRequest(
      id: id,
      authorId: currentUserId(),
      authorName: currentUserName(),
      text: text.trim(),
      placeId: placeId,
      placeTitle: placeTitle?.trim(),
      latitude: latitude,
      longitude: longitude,
      createdAt: _now(),
      expiresAt: expiresAt ?? _now().add(defaultLifetime),
    );
    return id;
  }

  NeedRequest _own(String needId) {
    final need = _needs[needId];
    if (need == null || need.authorId != currentUserId()) {
      throw const RuleViolation('need_not_yours');
    }
    return need;
  }

  @override
  Future<void> closeNeed(String needId) async {
    final need = _own(needId);
    _needs[needId] = need.copyWith(status: NeedStatus.closed);
  }

  @override
  Future<void> deleteNeed(String needId) async {
    _own(needId);
    _needs.remove(needId);
    _responses.remove(needId);
  }

  @override
  Future<void> respond(String needId, {String? text}) async {
    final need = _needs[needId];
    if (need == null) throw const RuleViolation('need_not_found');
    if (need.authorId == currentUserId()) throw const RuleViolation('need_is_yours');
    if (!need.isVisible) throw const RuleViolation('need_closed');

    final list = _responses.putIfAbsent(needId, () => []);
    final trimmed = text?.trim();
    final response = NeedResponse(
      id: 'local-response-${_nextId++}',
      authorId: currentUserId(),
      authorName: currentUserName(),
      text: trimmed == null || trimmed.isEmpty ? null : trimmed,
      createdAt: _now(),
    );
    final index = list.indexWhere((r) => r.authorId == currentUserId());
    if (index == -1) {
      list.add(response);
    } else {
      list[index] = response;
    }
  }

  @override
  Future<void> withdrawResponse(String needId) async {
    _responses[needId]?.removeWhere((r) => r.authorId == currentUserId());
  }

  @override
  Future<List<NeedResponse>> loadResponses(String needId) async =>
      List.of(_responses[needId] ?? const <NeedResponse>[]);

  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  void _seed() {
    final now = _now();
    _needs['seed-need-tv'] = NeedRequest(
      id: 'seed-need-tv',
      authorId: 'person-6',
      authorName: 'Ника',
      text: 'Нужно повесить телевизор на стену, кронштейн есть',
      latitude: 43.5810,
      longitude: 39.7260,
      createdAt: now.subtract(const Duration(hours: 5)),
      expiresAt: now.add(const Duration(days: 2)),
    );
    _needs['seed-need-tennis'] = NeedRequest(
      id: 'seed-need-tennis',
      authorId: 'person-3',
      authorName: 'Саша',
      text: 'Ищу напарника для тенниса по утрам',
      placeTitle: 'Корты у Ривьеры',
      latitude: 43.5870,
      longitude: 39.7180,
      createdAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 6)),
    );
  }
}
