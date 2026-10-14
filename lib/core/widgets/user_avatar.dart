import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Картинка по ссылке или по локальному пути: в режиме заглушек аватар и
/// фото — это файл на устройстве (на вебе — blob), а не URL хранилища.
ImageProvider imageProviderFor(String url) {
  if (url.startsWith('http')) return CachedNetworkImageProvider(url);
  if (kIsWeb) return NetworkImage(url);
  return FileImage(File(url));
}

/// Переход на профиль человека. Своя же страница открывается тем же экраном —
/// он сам решает, какие действия показать.
void openProfile(BuildContext context, String userId) =>
    context.push('${Routes.user}/$userId');

/// Кайма вокруг аватара: золотая у команды проекта, зелёная у
/// тестировщиков (миграция 0087). Список короткий, грузится один раз после
/// входа ([AvatarRings.load]); без него аватары просто без каймы.
enum AvatarRing {
  gold(Color(0xFFC7A660)),
  green(Color(0xFF5E9E73)),

  /// Виртуальные авторы ChaWo (0090): честная метка «это не человек».
  violet(Color(0xFF8E7CC3));

  const AvatarRing(this.color);

  final Color color;
}

abstract final class AvatarRings {
  static final byUser = ValueNotifier<Map<String, AvatarRing>>(const {});

  /// [rows] — ответ profile_rings(): `[{profile_id, ring}]`.
  static void set(Iterable<Map<String, dynamic>> rows) {
    final rings = <String, AvatarRing>{};
    for (final row in rows) {
      final ring = switch (row['ring']) {
        'gold' => AvatarRing.gold,
        'green' => AvatarRing.green,
        'violet' => AvatarRing.violet,
        _ => null,
      };
      if (ring != null) rings[row['profile_id'] as String] = ring;
    }
    byUser.value = rings;
  }
}

/// Аватар человека. С [userId] он ещё и нажимается — открывает профиль:
/// так во всех местах, где виден человек (пост, комментарий, участник события,
/// уведомление), тап по аватару или имени ведёт в одно и то же место.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.userId,
    this.radius = 18,
    this.ringUserId,
  });

  final String name;
  final String? url;
  final String? userId;
  final double radius;

  /// Чья кайма, если аватар не нажимается ([userId] не задан), но известно,
  /// чей он: шапка чата, профиль, блик.
  final String? ringUserId;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.ink2,
      backgroundImage: url == null ? null : imageProviderFor(url!),
      child: url != null
          ? null
          : Text(
              (name.isEmpty ? '?' : name.characters.first).toUpperCase(),
              style: AppTypography.serif(
                radius * 0.9,
                color: AppColors.primaryTint,
              ),
            ),
    );

    final ringId = ringUserId ?? userId;
    final ringed = ringId == null
        ? avatar
        : ValueListenableBuilder<Map<String, AvatarRing>>(
            valueListenable: AvatarRings.byUser,
            child: avatar,
            builder: (_, rings, child) {
              final ring = rings[ringId];
              if (ring == null) return child!;
              // Кольцо снаружи, с тонким зазором: размер аватара не меняется
              // для соседей по строке — кольцо ложится поверх отступа.
              final width = radius >= 30 ? 2.5 : 1.8;
              return Container(
                padding: EdgeInsets.all(width + 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring.color, width: width),
                ),
                child: child,
              );
            },
          );

    final id = userId;
    if (id == null) return ringed;

    return Semantics(
      button: true,
      label: 'Профиль: $name',
      child: InkResponse(
        onTap: () => openProfile(context, id),
        radius: radius + 6,
        child: ringed,
      ),
    );
  }
}
