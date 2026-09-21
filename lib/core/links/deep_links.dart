import '../router/app_router.dart';

/// Объекты, на которые можно сослаться. Новый тип ссылки — это значение здесь
/// и строка в [DeepLinks.locationFor]; ни шаринг, ни уведомления, ни разбор
/// входящих ссылок переписывать не нужно.
enum LinkTarget {
  post('post'),
  event('event'),
  place('place'),
  profile('profile'),
  route('route');

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
  const DeepLink(this.target, this.id);

  final LinkTarget target;
  final String id;

  /// Экран приложения, на который ведёт ссылка.
  String get location => DeepLinks.locationFor(target, id);

  @override
  bool operator ==(Object other) =>
      other is DeepLink && other.target == target && other.id == id;

  @override
  int get hashCode => Object.hash(target, id);
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
    return target == null ? null : DeepLink(target, id);
  }

  static String locationFor(LinkTarget target, String id) => switch (target) {
    LinkTarget.post => '${Routes.posts}/$id',
    LinkTarget.event => '${Routes.eventDetail}/$id',
    LinkTarget.place => '${Routes.places}/$id',
    LinkTarget.profile => '${Routes.user}/$id',
    LinkTarget.route => '${Routes.routes}/$id',
  };
}
