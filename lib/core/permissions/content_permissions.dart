/// Нет прав на действие: чужой пост нельзя править или удалять, на свой нельзя
/// жаловаться. Бросается ещё до запроса, а сервер (RLS, права на колонки,
/// политика жалоб) проверяет то же самое независимо от клиента.
class PermissionDeniedException implements Exception {
  const PermissionDeniedException([this.message = 'Нет прав на это действие']);

  final String message;

  @override
  String toString() => message;
}

/// Единое место, где решается, что можно делать с материалом (пост, событие,
/// маршрут, профиль). Экраны спрашивают отсюда, а не сравнивают id у себя —
/// иначе правило «чужое/своё» расползается по десятку виджетов и однажды
/// расходится.
class ContentPermissions {
  const ContentPermissions({required this.viewerId, required this.ownerId});

  final String? viewerId;
  final String ownerId;

  bool get isOwner => viewerId != null && viewerId == ownerId;

  // Действия над собственным материалом.
  bool get canEdit => isOwner;
  bool get canDelete => isOwner;
  bool get canChangeVisibility => isOwner;

  // Действия над чужим материалом.
  bool get canReport => viewerId != null && !isOwner;
  bool get canBlockAuthor => viewerId != null && !isOwner;
  bool get canHideAuthor => viewerId != null && !isOwner;
  bool get canFollowAuthor => viewerId != null && !isOwner;

  /// Бросает [PermissionDeniedException], если действие только для владельца.
  void requireOwner() {
    if (!isOwner) throw const PermissionDeniedException('Это чужая публикация');
  }

  /// Бросает [PermissionDeniedException] при попытке пожаловаться на своё.
  void requireForeign() {
    if (isOwner) {
      throw const PermissionDeniedException(
        'На собственную публикацию пожаловаться нельзя',
      );
    }
  }
}
