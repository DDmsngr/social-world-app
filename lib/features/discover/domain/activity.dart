import 'dart:math' as math;

/// Что можно включить в слой активности. Совпадает со значениями `in_kinds`
/// у серверной функции `city_activity`.
enum MapLayer {
  events('События', 'events'),
  places('Места', 'places'),
  people('Люди', 'people'),
  moments('Моменты', 'moments');

  const MapLayer(this.label, this.wire);

  final String label;
  final String wire;
}

/// «Где сейчас происходит жизнь» или «где спокойнее». Оба режима читают одну
/// и ту же оценку активности: спокойнее — это её обратная сторона, а не
/// отдельная модель. Пользователю для этого не нужно показывать своё
/// положение.
enum ActivityMode {
  // Короткие подписи: этот текст делит нижнюю панель с кнопкой «Рядом» и не
  // должен наезжать на неё на узких экранах.
  lively('Сейчас'),
  calm('Спокойнее');

  const ActivityMode(this.label);

  final String label;
}

/// Коэффициенты первой версии модели. Живут в одном месте и зеркалят таблицу
/// `activity_config` на сервере (миграция 0016): меняются значениями, а не
/// правкой логики. Клиентский [ActivityCalculator] использует их же в режиме
/// заглушек, чтобы карта без бэкенда считала то же самое.
class ActivityConfig {
  const ActivityConfig({
    this.cellSizeM = 600,
    this.spreadM = 450,
    this.wEvent = 3.0,
    this.wParticipant = 0.15,
    this.wPlace = 0.6,
    this.wMoment = 1.5,
    this.halfLifeEventH = 3.0,
    this.halfLifeMomentH = 6.0,
    this.eventHorizonH = 12.0,
    this.eventPastH = 2.0,
    this.momentMaxAgeH = 36.0,
    this.refScore = 6.0,
    this.minScore = 0.4,
  });

  static const defaults = ActivityConfig();

  /// Размер ячейки сетки, метры.
  final double cellSizeM;

  /// Радиус сглаживания: вклад объекта затухает по гауссу с этим масштабом.
  final double spreadM;

  final double wEvent;
  final double wParticipant;
  final double wPlace;
  final double wMoment;

  /// Период полураспада веса по времени, часы.
  final double halfLifeEventH;
  final double halfLifeMomentH;

  /// События дальше этого горизонта в слой не входят.
  final double eventHorizonH;

  /// Закончившиеся события учитываются не дольше этого времени.
  final double eventPastH;

  /// Моменты старше этого в слой не входят.
  final double momentMaxAgeH;

  /// Вес, принимаемый за «максимум»: одинокое место не должно выглядеть пиком.
  final double refScore;

  /// Зоны слабее этого веса не отдаются.
  final double minScore;
}

enum ActivityKind { event, place, moment }

/// Объект, из которого складывается активность. Собирается из событий,
/// мест и постов; сам про экраны и репозитории ничего не знает.
class ActivityObject {
  const ActivityObject({
    required this.kind,
    required this.latitude,
    required this.longitude,
    this.category,
    this.participants = 0,
    this.startsAt,
    this.endsAt,
    this.createdAt,
  });

  final ActivityKind kind;
  final double latitude;
  final double longitude;
  final String? category;

  /// Только для событий.
  final int participants;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Только для моментов.
  final DateTime? createdAt;
}

/// Запрос к слою: что считаем, вокруг чего и на какой момент времени. Момент
/// [at] — задел под временную шкалу: та же функция посчитает «что будет в 20:00».
class ActivityQuery {
  const ActivityQuery({
    required this.latitude,
    required this.longitude,
    required this.at,
    this.radiusMeters = 5000,
    this.layers = const {MapLayer.events, MapLayer.places, MapLayer.moments},
    this.categories = const {},
  });

  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime at;
  final Set<MapLayer> layers;
  final Set<String> categories;

  /// Ключ для сравнения запросов: пересчёт нужен, только если что-то из
  /// перечисленного реально поменялось. Время округляется до минуты, иначе
  /// каждая перерисовка считалась бы «новым» запросом.
  String get cacheKey => [
    latitude.toStringAsFixed(4),
    longitude.toStringAsFixed(4),
    radiusMeters,
    (layers.map((l) => l.wire).toList()..sort()).join(','),
    (categories.toList()..sort()).join(','),
    at.millisecondsSinceEpoch ~/ 60000,
  ].join('|');
}

/// Готовая зона: центр ячейки и нормированная (0..1) оценка активности.
class ActivityCell {
  const ActivityCell({
    required this.latitude,
    required this.longitude,
    required this.score,
    required this.radiusMeters,
    this.eventCount = 0,
    this.placeCount = 0,
    this.momentCount = 0,
  });

  final double latitude;
  final double longitude;

  /// 0..1 относительно самой сильной зоны в выборке (но не меньше опорного
  /// веса `refScore`).
  final double score;
  final int radiusMeters;
  final int eventCount;
  final int placeCount;
  final int momentCount;

  /// Интенсивность для рисования в выбранном режиме, 0..1; 0 — не рисовать.
  ///
  /// «Спокойнее» — обратная сторона той же оценки: это зоны, где что-то есть
  /// (место, куда можно пойти), но живости мало.
  double intensityFor(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.lively:
        return score;
      case ActivityMode.calm:
        if (placeCount == 0 || score >= calmCeiling) return 0;
        return 1 - score / calmCeiling;
    }
  }

  /// Выше этой оценки зона уже не считается спокойной.
  static const calmCeiling = 0.35;
}

/// Детерминированный расчёт активности: тот же алгоритм, что и в SQL-функции
/// `city_activity`. Нужен там, где сервера нет (режим заглушек), и как
/// исполняемая спецификация для тестов.
///
/// Цепочка: релевантные объекты → вес (тип, участники, свежесть) → сглаженная
/// сумма по ячейкам сетки → нормировка.
abstract final class ActivityCalculator {
  static List<ActivityCell> compute(
    List<ActivityObject> objects,
    ActivityQuery query, {
    ActivityConfig config = ActivityConfig.defaults,
  }) {
    final weighted = <_Weighted>[];

    for (final object in objects) {
      final kindLayer = switch (object.kind) {
        ActivityKind.event => MapLayer.events,
        ActivityKind.place => MapLayer.places,
        ActivityKind.moment => MapLayer.moments,
      };
      if (!query.layers.contains(kindLayer)) continue;
      if (query.categories.isNotEmpty &&
          !query.categories.contains(object.category)) {
        continue;
      }

      final metersFromCenter = _distance(
        query.latitude,
        query.longitude,
        object.latitude,
        object.longitude,
      );
      if (metersFromCenter > query.radiusMeters) continue;

      final weight = weightOf(object, query.at, config);
      if (weight <= 0) continue;
      weighted.add(_Weighted(object, weight));
    }
    if (weighted.isEmpty) return const [];

    // Ячейки — по сетке в метрах вокруг центра запроса.
    final cosLat = math.cos(query.latitude * math.pi / 180);
    const metersPerDegree = 111320.0;
    (double, double) toMeters(ActivityObject o) => (
      (o.longitude - query.longitude) * metersPerDegree * cosLat,
      (o.latitude - query.latitude) * metersPerDegree,
    );

    final cells = <(int, int), _Bucket>{};
    for (final item in weighted) {
      final (x, y) = toMeters(item.object);
      final key = ((x / config.cellSizeM).round(), (y / config.cellSizeM).round());
      cells.putIfAbsent(key, _Bucket.new).add(item.object.kind);
    }

    final raws = <(int, int), double>{};
    for (final key in cells.keys) {
      final cx = key.$1 * config.cellSizeM;
      final cy = key.$2 * config.cellSizeM;
      var sum = 0.0;
      for (final item in weighted) {
        final (x, y) = toMeters(item.object);
        final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
        if (d > config.spreadM * 2.5) continue;
        sum += item.weight * math.exp(-math.pow(d / config.spreadM, 2));
      }
      raws[key] = sum;
    }

    final peak = raws.values.fold<double>(0, math.max);
    final scale = math.max(peak, config.refScore);

    final result = <ActivityCell>[];
    for (final entry in raws.entries) {
      if (entry.value < config.minScore) continue;
      final (kx, ky) = entry.key;
      final bucket = cells[entry.key]!;
      result.add(
        ActivityCell(
          latitude: query.latitude + (ky * config.cellSizeM) / metersPerDegree,
          longitude:
              query.longitude + (kx * config.cellSizeM) / (metersPerDegree * cosLat),
          score: math.min(1, entry.value / scale),
          radiusMeters: config.cellSizeM.round(),
          eventCount: bucket.events,
          placeCount: bucket.places,
          momentCount: bucket.moments,
        ),
      );
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result.length > 300 ? result.sublist(0, 300) : result;
  }

  /// Вес одного объекта на момент [at]. Ноль — объект в расчёт не входит.
  static double weightOf(
    ActivityObject object,
    DateTime at,
    ActivityConfig config,
  ) {
    switch (object.kind) {
      case ActivityKind.place:
        return config.wPlace;

      case ActivityKind.moment:
        final created = object.createdAt;
        if (created == null) return 0;
        final ageH = at.difference(created).inMinutes / 60.0;
        if (ageH < 0 || ageH > config.momentMaxAgeH) return 0;
        return config.wMoment * math.pow(0.5, ageH / config.halfLifeMomentH);

      case ActivityKind.event:
        final starts = object.startsAt;
        if (starts == null) return 0;
        final ends = object.endsAt ?? starts.add(const Duration(hours: 2));

        double dtH;
        if (at.isBefore(starts)) {
          dtH = starts.difference(at).inMinutes / 60.0;
          if (dtH > config.eventHorizonH) return 0;
        } else if (!at.isAfter(ends)) {
          dtH = 0; // Идёт прямо сейчас.
        } else {
          dtH = at.difference(ends).inMinutes / 60.0;
          if (dtH > config.eventPastH) return 0;
        }

        final crowd = 1 + config.wParticipant * math.min(object.participants, 50);
        return config.wEvent * crowd * math.pow(0.5, dtH / config.halfLifeEventH);
    }
  }

  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }
}

class _Weighted {
  _Weighted(this.object, this.weight);

  final ActivityObject object;
  final double weight;
}

class _Bucket {
  int events = 0;
  int places = 0;
  int moments = 0;

  void add(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.event:
        events++;
      case ActivityKind.place:
        places++;
      case ActivityKind.moment:
        moments++;
    }
  }
}
