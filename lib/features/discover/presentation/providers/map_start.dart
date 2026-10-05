import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/location/device_position.dart';
import '../../domain/activity.dart';

/// Куда смотрит карта при открытии Pulse.
enum MapStart {
  /// С того места, где вы сейчас. Нет разрешения или вы в другом городе —
  /// как «самое активное».
  myLocation('С моего местоположения'),

  /// С самой оживлённой зоны выбранного города.
  hotspot('С самого активного места в городе');

  const MapStart(this.label);
  final String label;

  static const _key = 'map_start';

  static Future<MapStart> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      for (final value in values) {
        if (value.name == saved) return value;
      }
    } catch (_) {}
    return MapStart.myLocation;
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, name);
    } catch (error) {
      AppLog.add('Старт карты не сохранился: $error');
    }
  }
}

typedef MapStartTarget = ({double latitude, double longitude, double zoom});

/// Дальше этого от центра города «моё место» считаем чужим городом и
/// открываем карту на активной зоне.
const _maxDistanceFromCityMeters = 80000.0;

/// Точка, на которую навести карту при первом открытии. null — оставить
/// центр города.
Future<MapStartTarget?> planMapStart({
  required MapStart mode,
  required double cityLatitude,
  required double cityLongitude,
  required Future<List<ActivityCell>> Function() loadActivity,
}) async {
  if (mode == MapStart.myLocation && await hasLocationPermission()) {
    try {
      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 6),
            ),
          );
      final away = Geolocator.distanceBetween(
        cityLatitude,
        cityLongitude,
        position.latitude,
        position.longitude,
      );
      if (away <= _maxDistanceFromCityMeters) {
        return (
          latitude: position.latitude,
          longitude: position.longitude,
          zoom: 15.5,
        );
      }
    } catch (error) {
      AppLog.add('Старт карты: положение не определилось: $error');
    }
  }
  return hottestZone(await _safe(loadActivity));
}

Future<List<ActivityCell>> _safe(Future<List<ActivityCell>> Function() load) async {
  try {
    return await load().timeout(const Duration(seconds: 8));
  } catch (error) {
    AppLog.add('Старт карты: активность не загрузилась: $error');
    return const [];
  }
}

/// Самая оживлённая зона: наибольшая оценка активности.
MapStartTarget? hottestZone(List<ActivityCell> cells) {
  ActivityCell? best;
  for (final cell in cells) {
    if (cell.score <= 0.04) continue;
    if (best == null || cell.score > best.score) best = cell;
  }
  if (best == null) return null;
  return (latitude: best.latitude, longitude: best.longitude, zoom: 14.5);
}
