import 'dart:math' as math;

import '../../../core/errors/rule_violation.dart';
import '../domain/entities/quest.dart';
import '../domain/repositories/quests_repository.dart';

/// Квесты в памяти, пока Supabase не поднят. Правила — те же, что в функциях
/// миграции 0023 (лимит мест, автоодобрение без лимита, код прибытия, кто
/// видит участников), чтобы сценарий проходился целиком и чтобы тесты
/// проверяли именно их.
class LocalQuestsRepository implements QuestsRepository {
  LocalQuestsRepository({
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

  final _quests = <String, _StoredQuest>{};
  final _participations = <String, _StoredParticipation>{};
  final _moments = <String, List<QuestMoment>>{};
  final _consents = <String, QuestRulesConsent>{};
  var _nextId = 0;

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final _random = math.Random();

  String _newCode() => String.fromCharCodes(
    List.generate(8, (_) => _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length))),
  );

  // ── чтение ────────────────────────────────────────────────────────────────

  int _taken(String questId) => _participations.values
      .where((p) => p.questId == questId && p.status.holdsSlot)
      .length;

  _StoredParticipation? _mine(String questId) {
    final me = currentUserId();
    for (final p in _participations.values) {
      if (p.questId == questId && p.profileId == me) return p;
    }
    return null;
  }

  DateTime? _overAt(_StoredQuest q) {
    if (q.finishedAt != null) return q.finishedAt;
    final ends = q.endsAt;
    return ends != null && !ends.isAfter(_now()) ? ends : null;
  }

  bool _isOpen(_StoredQuest q) =>
      q.status == QuestStatus.active && _overAt(q) == null;

  Quest _toQuest(_StoredQuest q) {
    final over = _overAt(q);
    return Quest(
      id: q.id,
      authorId: q.authorId,
      authorName: q.authorName,
      title: q.title,
      description: q.description,
      extraInfo: q.extraInfo,
      photoUrl: q.photoUrl,
      placeId: q.placeId,
      placeTitle: q.placeTitle,
      latitude: q.latitude,
      longitude: q.longitude,
      startsAt: q.startsAt,
      endsAt: q.endsAt,
      maxParticipants: q.maxParticipants,
      participantCount: _taken(q.id),
      status: q.status == QuestStatus.active && over != null
          ? QuestStatus.finished
          : q.status,
      finishedAt: over,
      myStatus: _mine(q.id)?.status,
      momentCount: _moments[q.id]?.length ?? 0,
      isTrail: over != null,
      createdAt: q.createdAt,
    );
  }

  @override
  Future<List<Quest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
    DateTime? at,
  }) async {
    final moment = at ?? _now();
    final result = <Quest>[];
    for (final q in _quests.values) {
      if (q.status == QuestStatus.cancelled || q.latitude == null) continue;
      if (_distance(latitude, longitude, q.latitude!, q.longitude!) > radiusMeters) {
        continue;
      }
      final over = _overAt(q);
      final hasMoments = (_moments[q.id]?.isNotEmpty ?? false);
      // Идёт — или завершён меньше суток назад и оставил Moments (п. 42).
      if (over != null &&
          !(hasMoments && over.isAfter(moment.subtract(const Duration(hours: 24))))) {
        continue;
      }
      result.add(_toQuest(q));
    }
    result.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return result;
  }

  @override
  Future<Quest?> loadQuest(String questId) async {
    final q = _quests[questId];
    return q == null ? null : _toQuest(q);
  }

  @override
  Future<List<Quest>> myQuests({bool activeOnly = false}) async {
    final me = currentUserId();
    final result = <Quest>[];
    for (final p in _participations.values) {
      if (p.profileId != me) continue;
      if (p.status == QuestParticipationStatus.rejected ||
          p.status == QuestParticipationStatus.removed) {
        continue;
      }
      final q = _quests[p.questId];
      if (q == null) continue;
      if (activeOnly && !(p.status.isActive && _isOpen(q))) continue;
      result.add(_toQuest(q));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<List<Quest>> questsIAuthored({bool activeOnly = false}) async {
    final me = currentUserId();
    return [
      for (final q in _quests.values)
        if (q.authorId == me && (!activeOnly || _isOpen(q))) _toQuest(q),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<QuestParticipation>> loadParticipants(String questId) async {
    final q = _quests[questId];
    if (q == null) return const [];
    final me = currentUserId();
    final isAuthor = q.authorId == me;
    final iHoldSlot = _mine(questId)?.status.holdsSlot ?? false;
    if (!isAuthor && !iHoldSlot) return const [];

    final list = [
      for (final p in _participations.values)
        if (p.questId == questId && (isAuthor || p.status.holdsSlot)) p.toParticipation(),
    ];
    list.sort((a, b) {
      final ar = a.status == QuestParticipationStatus.requested ? 0 : 1;
      final br = b.status == QuestParticipationStatus.requested ? 0 : 1;
      return ar != br ? ar - br : a.requestedAt.compareTo(b.requestedAt);
    });
    return list;
  }

  @override
  Future<List<QuestMoment>> loadMoments(String questId) async =>
      List.of(_moments[questId] ?? const <QuestMoment>[]);

  // ── организатор ───────────────────────────────────────────────────────────

  @override
  Future<String> createQuest({
    required String title,
    required DateTime startsAt,
    String? description,
    String? extraInfo,
    String? photoPath,
    DateTime? endsAt,
    String? placeId,
    String? placeTitle,
    double? latitude,
    double? longitude,
    int? maxParticipants,
  }) async {
    final consent = _consents[currentUserId()];
    if (consent == null || !consent.isCurrent) {
      throw const RuleViolation('quest_rules_required');
    }
    if (startsAt.isBefore(_now().subtract(const Duration(hours: 1)))) {
      throw const RuleViolation('quest_starts_in_past');
    }
    if ((latitude == null) != (longitude == null)) {
      throw const RuleViolation('quest_bad_point');
    }
    final id = 'local-quest-${_nextId++}';
    _quests[id] = _StoredQuest(
      id: id,
      authorId: currentUserId(),
      authorName: currentUserName(),
      title: title.trim(),
      description: _clean(description),
      extraInfo: _clean(extraInfo),
      // Файл с устройства в заглушке не загружается — фото остаётся пустым.
      photoUrl: null,
      placeId: placeId,
      placeTitle: _clean(placeTitle),
      latitude: latitude,
      longitude: longitude,
      startsAt: startsAt,
      endsAt: endsAt,
      maxParticipants: maxParticipants,
      code: _newCode(),
      createdAt: _now(),
    );
    return id;
  }

  _StoredQuest _own(String questId) {
    final q = _quests[questId];
    if (q == null || q.authorId != currentUserId()) {
      throw const RuleViolation('quest_not_yours');
    }
    return q;
  }

  @override
  Future<void> decideRequest({
    required String participationId,
    required bool approved,
  }) async {
    final p = _participations[participationId];
    if (p == null) throw const RuleViolation('quest_request_not_found');
    final q = _own(p.questId);
    if (p.status != QuestParticipationStatus.requested) return;
    if (approved) {
      if (!_isOpen(q)) throw const RuleViolation('quest_closed');
      if (q.maxParticipants != null && _taken(q.id) >= q.maxParticipants!) {
        throw const RuleViolation('quest_full');
      }
    }
    p.status = approved
        ? QuestParticipationStatus.approved
        : QuestParticipationStatus.rejected;
  }

  @override
  Future<void> removeParticipant(String participationId) async {
    final p = _participations[participationId];
    if (p == null) throw const RuleViolation('quest_request_not_found');
    _own(p.questId);
    if (p.status.isActive) p.status = QuestParticipationStatus.removed;
  }

  @override
  Future<void> finishQuest(String questId) async {
    final q = _own(questId);
    if (q.status != QuestStatus.active) return;
    q.status = QuestStatus.finished;
    q.finishedAt = _now();
  }

  @override
  Future<void> cancelQuest(String questId) async {
    final q = _own(questId);
    if (q.status != QuestStatus.active) return;
    q.status = QuestStatus.cancelled;
    q.finishedAt = _now();
  }

  @override
  Future<String> arrivalCode(String questId) async => _own(questId).code;

  @override
  Future<String> rotateArrivalCode(String questId) async {
    final q = _own(questId);
    q.code = _newCode();
    return q.code;
  }

  // ── участник ──────────────────────────────────────────────────────────────

  @override
  Future<QuestParticipationStatus> requestJoin(String questId) async {
    final q = _quests[questId];
    if (q == null) throw const RuleViolation('quest_not_found');
    if (q.authorId == currentUserId()) throw const RuleViolation('quest_is_yours');

    final existing = _mine(questId);
    if (existing != null) {
      if (existing.status.isActive) return existing.status;
      if (existing.status == QuestParticipationStatus.rejected ||
          existing.status == QuestParticipationStatus.removed) {
        throw const RuleViolation('quest_denied');
      }
    }
    if (!_isOpen(q)) throw const RuleViolation('quest_closed');
    if (q.maxParticipants != null && _taken(q.id) >= q.maxParticipants!) {
      throw const RuleViolation('quest_full');
    }

    final status = q.maxParticipants == null
        ? QuestParticipationStatus.approved
        : QuestParticipationStatus.requested;
    if (existing != null) {
      existing
        ..status = status
        ..requestedAt = _now()
        ..arrivedAt = null
        ..completedAt = null;
    } else {
      final id = 'local-part-${_nextId++}';
      _participations[id] = _StoredParticipation(
        id: id,
        questId: questId,
        profileId: currentUserId(),
        displayName: currentUserName(),
        status: status,
        requestedAt: _now(),
      );
    }
    return status;
  }

  @override
  Future<void> withdraw(String questId) async {
    final p = _mine(questId);
    if (p != null && p.status.isActive) p.status = QuestParticipationStatus.withdrawn;
  }

  @override
  Future<void> completeParticipation(String questId) async {
    final p = _mine(questId);
    if (p != null && p.status == QuestParticipationStatus.completed) return;
    if (p == null || !p.status.holdsSlot) {
      throw const RuleViolation('quest_not_participating');
    }
    p
      ..status = QuestParticipationStatus.completed
      ..completedAt = _now();
  }

  @override
  Future<QuestParticipationStatus> confirmArrival({
    required String questId,
    required String code,
  }) async {
    final q = _quests[questId];
    if (q == null) throw const RuleViolation('quest_not_found');
    if (q.authorId == currentUserId()) throw const RuleViolation('quest_is_yours');
    if (normalizeArrivalCode(code) != q.code) throw const RuleViolation('quest_bad_code');
    if (!_isOpen(q)) throw const RuleViolation('quest_closed');

    final p = _mine(questId);
    if (p?.status == QuestParticipationStatus.arrived) return p!.status;
    if (p != null &&
        (p.status == QuestParticipationStatus.rejected ||
            p.status == QuestParticipationStatus.removed)) {
      throw const RuleViolation('quest_denied');
    }
    if (p?.status == QuestParticipationStatus.approved) {
      p!
        ..status = QuestParticipationStatus.arrived
        ..arrivedAt = _now();
      return p.status;
    }
    if (q.maxParticipants != null) throw const RuleViolation('quest_not_approved');

    if (p != null) {
      p
        ..status = QuestParticipationStatus.arrived
        ..requestedAt = _now()
        ..arrivedAt = _now()
        ..completedAt = null;
    } else {
      final id = 'local-part-${_nextId++}';
      _participations[id] = _StoredParticipation(
        id: id,
        questId: questId,
        profileId: currentUserId(),
        displayName: currentUserName(),
        status: QuestParticipationStatus.arrived,
        requestedAt: _now(),
      )..arrivedAt = _now();
    }
    return QuestParticipationStatus.arrived;
  }

  // ── правила ───────────────────────────────────────────────────────────────

  @override
  Future<QuestRulesConsent?> loadRulesConsent() async => _consents[currentUserId()];

  @override
  Future<void> acceptRules(int version) async {
    if (version != QuestRulesConsent.currentVersion) {
      throw const RuleViolation('quest_rules_outdated');
    }
    _consents[currentUserId()] = QuestRulesConsent(version: version, acceptedAt: _now());
  }

  /// Quest Moment в заглушке: лента живёт отдельно, здесь только строка
  /// истории квеста. Вызывает экран после публикации момента.
  void addMoment(String questId, QuestMoment moment) {
    _moments.putIfAbsent(questId, () => []).add(moment);
  }

  // ── служебное ─────────────────────────────────────────────────────────────

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

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
    _quests['seed-quest-coffee'] = _StoredQuest(
      id: 'seed-quest-coffee',
      authorId: 'person-8',
      authorName: 'Кофе у Серёги',
      title: '10 бесплатных кофе от «Кофе у Серёги»',
      description: 'Приходите, скажите, что вы из ChaWo, отсканируйте QR у бариста — '
          'и кофе за нами.',
      placeTitle: 'ул. Навагинская, 12',
      latitude: 43.5830,
      longitude: 39.7210,
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 10)),
      maxParticipants: 10,
      code: 'CHAWO123',
      createdAt: now.subtract(const Duration(hours: 3)),
    );
    _quests['seed-quest-bike'] = _StoredQuest(
      id: 'seed-quest-bike',
      authorId: 'person-3',
      authorName: 'Саша',
      title: 'Каждый вечер катаемся в Морском порту',
      description: 'Спокойный темп, около часа. Велосипед свой или прокат у порта.',
      placeTitle: 'Морской порт',
      latitude: 43.5775,
      longitude: 39.7188,
      startsAt: now.add(const Duration(hours: 2)),
      code: 'BIKE2345',
      createdAt: now.subtract(const Duration(days: 1)),
    );
    for (final (i, name) in const ['Лев', 'Алекс', 'Виктор'].indexed) {
      final id = 'seed-part-$i';
      _participations[id] = _StoredParticipation(
        id: id,
        questId: 'seed-quest-coffee',
        profileId: 'seed-person-$i',
        displayName: name,
        status: QuestParticipationStatus.approved,
        requestedAt: now.subtract(Duration(minutes: 40 - i * 10)),
      );
    }
  }
}


class _StoredQuest {
  _StoredQuest({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.startsAt,
    required this.code,
    required this.createdAt,
    this.description,
    this.extraInfo,
    this.photoUrl,
    this.placeId,
    this.placeTitle,
    this.latitude,
    this.longitude,
    this.endsAt,
    this.maxParticipants,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String? description;
  final String? extraInfo;
  final String? photoUrl;
  final String? placeId;
  final String? placeTitle;
  final double? latitude;
  final double? longitude;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int? maxParticipants;
  final DateTime createdAt;
  String code;
  QuestStatus status = QuestStatus.active;
  DateTime? finishedAt;
}

class _StoredParticipation {
  _StoredParticipation({
    required this.id,
    required this.questId,
    required this.profileId,
    required this.displayName,
    required this.status,
    required this.requestedAt,
  });

  final String id;
  final String questId;
  final String profileId;
  final String displayName;
  QuestParticipationStatus status;
  DateTime requestedAt;
  DateTime? arrivedAt;
  DateTime? completedAt;

  QuestParticipation toParticipation() => QuestParticipation(
    id: id,
    questId: questId,
    profileId: profileId,
    displayName: displayName,
    status: status,
    requestedAt: requestedAt,
    arrivedAt: arrivedAt,
    completedAt: completedAt,
  );
}
