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
  });

  final String name;
  final String? url;
  final String? userId;
  final double radius;

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

    final id = userId;
    if (id == null) return avatar;

    return Semantics(
      button: true,
      label: 'Профиль: $name',
      child: InkResponse(
        onTap: () => openProfile(context, id),
        radius: radius + 6,
        child: avatar,
      ),
    );
  }
}
