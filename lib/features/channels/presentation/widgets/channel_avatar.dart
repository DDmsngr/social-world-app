import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Аватар канала: картинка, если её поставили, иначе значок-рупор.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, this.url, this.radius = 20});

  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = url;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.ink,
      foregroundImage: image == null ? null : CachedNetworkImageProvider(image),
      child: Icon(Icons.campaign_outlined, color: AppColors.primaryTint, size: radius * 0.9),
    );
  }
}
