import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'user_avatar.dart';

/// Мини-аватарки внахлёст («кто идёт»). Порядок — как пришёл: сначала друзья.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.people,
    this.radius = 14,
    this.overlap = 8,
  });

  /// Имя и адрес картинки каждого.
  final List<({String name, String? url})> people;
  final double radius;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final step = radius * 2 - overlap;
    final ring = AppColors.card;

    return SizedBox(
      width: step * (people.length - 1) + radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < people.length; i++)
            Positioned(
              left: step * i,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 1.5),
                ),
                child: UserAvatar(
                  name: people[i].name,
                  url: people[i].url,
                  radius: radius - 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
