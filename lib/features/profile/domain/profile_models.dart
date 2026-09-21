/// Чужой аккаунт для меня: заблокирован целиком или только скрыт из ленты.
enum BlockKind {
  block,
  mute;

  static BlockKind? parse(dynamic raw) => switch (raw) {
    'block' => BlockKind.block,
    'mute' => BlockKind.mute,
    _ => null,
  };
}

/// Общая модель профиля — своего и чужого. Что из этого можно делать, решает
/// экран по `isMe`, а не отдельные классы: данные одни и те же.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.city,
    this.socialScore = 0,
    this.followerCount = 0,
    this.followingCount = 0,
    this.followedByMe = false,
    this.blockKind,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? city;
  final int socialScore;
  final int followerCount;
  final int followingCount;
  final bool followedByMe;
  final BlockKind? blockKind;

  UserProfile copyWith({
    int? followerCount,
    bool? followedByMe,
    BlockKind? blockKind,
    bool clearBlock = false,
  }) => UserProfile(
    id: id,
    displayName: displayName,
    avatarUrl: avatarUrl,
    bio: bio,
    city: city,
    socialScore: socialScore,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount,
    followedByMe: followedByMe ?? this.followedByMe,
    blockKind: clearBlock ? null : (blockKind ?? this.blockKind),
  );
}

/// Строка списка «Заблокированные».
class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.displayName,
    required this.kind,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final BlockKind kind;
}

/// Результат поиска людей.
class ProfileHit {
  const ProfileHit({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
}
