import '../router/app_router.dart';

/// Объекты, на которые можно сослаться. Новый тип ссылки — это значение здесь
/// и строка в [DeepLinks.locationFor]; ни шаринг, ни уведомления, ни разбор
/// входящих ссылок переписывать не нужно.
enum LinkTarget {
  post('post'),
  event('event'),
  place('place'),
  profile('profile'),
  route('route'),
  quest('quest'),
  need('need');

  const LinkTarget(this.segment);

  /// Как объект называется в адресе.
  final String segment;

  static LinkTarget? fromSegment(String value) {
    for (final target in values) {
      if (target.segment == value) return target;
    }
    return null;
  }
}

class DeepLink {
  const DeepLink(this.target, this.id, {this.arrivalCode});

  final LinkTarget target;
  final String id;

  /// Код прибытия из QR квеста (`?arrive=`): карточка квеста сразу
  /// предлагает отметиться на месте.
  final String? arrivalCode;

  /// Экран приложения, на который ведёт ссылка.
  String get location =>
      DeepLinks.locationFor(target, id, arrivalCode: arrivalCode);

  @override
  bool operator ==(Object other) =>
      other is DeepLink &&
      other.target == target &&
      other.id == id &&
      other.arrivalCode == arrivalCode;

  @override
  int get hashCode => Object.hash(target, id, arrivalCode);
}

abstract final class DeepLinks {
  static const scheme = 'socialworld';

  /// Куда ведёт ссылка, которой делятся. Это страница-посредник: если
  /// приложение стоит — ссылка открывает его на нужном объекте, если нет —
  /// страница показывает, что это за объект, и куда скачать приложение.
  /// Адрес переопределяется `--dart-define=SHARE_BASE_URL=...`, когда у
  /// проекта появится свой домен.
  static const shareBase = String.fromEnvironment(
    'SHARE_BASE_URL',
    defaultValue: 'https://ddmsngr.github.io/social-world/o',
  );

  static final _id = RegExp(r'^[A-Za-z0-9_-]{4,64}$');
  static final _code = RegExp(r'^[A-Za-z0-9]{4,16}$');

  /// Что зашито в QR квеста: `socialworld://quest/<id>?arrive=<код>`.
  /// Открывается системной камерой — отдельный сканер в приложении не нужен.
  static Uri arrivalUri(String questId, String code) => Uri(
    scheme: scheme,
    host: LinkTarget.quest.segment,
    path: '/$questId',
    queryParameters: {'arrive': code},
  );

  /// Ссылка, которой делятся: `https://…/o/event/<id>`.
  static Uri shareUri(LinkTarget target, String id) =>
      Uri.parse('$shareBase/${target.segment}/$id');

  /// Прямая ссылка в приложение: `socialworld://event/<id>`.
  static Uri appUri(LinkTarget target, String id) =>
      Uri(scheme: scheme, host: target.segment, path: '/$id');

  /// Разбирает и `socialworld://post/<id>`, и `https://<база шаринга>/post/<id>`.
  /// Всё остальное (включая `socialworld://auth-callback`) — `null`.
  static DeepLink? parse(Uri uri) {
    String? segment;
    String? id;

    if (uri.scheme == scheme) {
      segment = uri.host;
      id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (uri.scheme == 'https' || uri.scheme == 'http') {
      final base = Uri.parse(shareBase);
      if (uri.host != base.host) return null;
      // Берём последние два сегмента: префикс пути (`/social-world/o`)
      // может поменяться вместе с доменом.
      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      if (parts.length < 2) return null;
      segment = parts[parts.length - 2];
      id = parts.last;
    }

    if (segment == null || id == null || !_id.hasMatch(id)) return null;
    final target = LinkTarget.fromSegment(segment);
    if (target == null) return null;
    final code = uri.queryParameters['arrive'];
    return DeepLink(
      target,
      id,
      arrivalCode: target == LinkTarget.quest && code != null && _code.hasMatch(code)
          ? code
          : null,
    );
  }

  static String locationFor(LinkTarget target, String id, {String? arrivalCode}) =>
      switch (target) {
        LinkTarget.post => '${Routes.posts}/$id',
        LinkTarget.event => '${Routes.eventDetail}/$id',
        LinkTarget.place => '${Routes.places}/$id',
        LinkTarget.profile => '${Routes.user}/$id',
        LinkTarget.route => '${Routes.routes}/$id',
        LinkTarget.quest => arrivalCode == null
            ? '${Routes.questDetail}/$id'
            : '${Routes.questDetail}/$id?arrive=$arrivalCode',
        LinkTarget.need => '${Routes.needDetail}/$id',
      };
}
