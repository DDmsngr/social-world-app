import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'live_map_marker.dart';

/// Веб-версия: MapKit на вебе не собирается — показываем координаты списком.
class LiveMap extends StatelessWidget {
  const LiveMap({super.key, required this.markers, this.frameKey = 0});

  final List<LiveMapMarker> markers;
  final int frameKey;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.ink,
    child: Center(
      child: Text(
        [for (final m in markers) '${m.label}: ${m.latitude.toStringAsFixed(5)}, ${m.longitude.toStringAsFixed(5)}']
            .join('\n'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textDim),
      ),
    ),
  );
}
