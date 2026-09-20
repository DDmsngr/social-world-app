import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/location/geo_privacy.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import 'discover_providers.dart';

const _prefsKey = 'presence_enabled';

/// Как часто обновляется точка, пока приложение открыто. `nearby_profiles`
/// считает точку протухшей через два часа, так что запас здесь огромный —
/// чаще незачем будить GPS.
const _interval = Duration(minutes: 15);

/// Видно ли меня другим на карте «Рядом».
///
/// Хранится на устройстве, а не в профиле: строка в `locations` существует
/// ровно пока присутствие включено, выключение её удаляет — отдельного флага
/// на сервере не нужно.
final initialPresenceEnabledProvider = Provider<bool>((_) => true);

Future<bool> loadPresenceEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? true;
}

class PresenceEnabledController extends Notifier<bool> {
  @override
  bool build() {
    ref.keepAlive();
    return ref.read(initialPresenceEnabledProvider);
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);

    // Выключили — точка должна исчезнуть сразу, а не протухать два часа.
    if (!value) {
      try {
        await ref.read(discoverRepositoryProvider).clearPresence();
      } catch (error) {
        AppLog.add('Присутствие: не удалось убрать точку: $error');
      }
    }
  }
}

final presenceEnabledProvider =
    NotifierProvider<PresenceEnabledController, bool>(
      PresenceEnabledController.new,
    );

/// Что именно уйдёт в базу при текущем состоянии — вынесено отдельно, чтобы
/// проверять решение тестами без GPS, сети и платформенных каналов.
BlurredPoint? blurredPresenceFor({
  required bool enabled,
  required AppUser? user,
  required double? latitude,
  required double? longitude,
}) {
  if (!enabled || user == null || latitude == null || longitude == null) {
    return null;
  }

  // Соль — идентификатор человека: сетка размытия у каждого своя, иначе по
  // общим границам ячеек её можно было бы восстановить.
  return GeoPrivacy.blur(
    latitude: latitude,
    longitude: longitude,
    salt: user.id,
    // В таблице стоит check (blur_radius_m >= 200). Значение меньше уронило бы
    // каждую публикацию, и человек молча пропал бы с карты навсегда.
    radiusMeters: user.locationBlurM.clamp(200, 10000).toDouble(),
  );
}

/// Публикует размытую точку, пока открыт экран карты.
///
/// Разрешение на геолокацию сам не запрашивает: его уже спрашивает слой
/// местоположения на карте и кнопка «к себе». Нет разрешения — молча ничего
/// не публикуем, лишнего системного окна человек не увидит.
class PresencePublisher {
  PresencePublisher(this._ref) {
    _lifecycle = AppLifecycleListener(onResume: publishNow);
    _timer = Timer.periodic(_interval, (_) => publishNow());
    publishNow();
  }

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;
  late final Timer _timer;
  var _disposed = false;
  var _busy = false;

  Future<void> publishNow() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      if (!_ref.read(presenceEnabledProvider)) return;
      if (WidgetsBinding.instance.lifecycleState !=
          AppLifecycleState.resumed) {
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final position = await Geolocator.getCurrentPosition();
      if (_disposed) return;

      final point = blurredPresenceFor(
        enabled: _ref.read(presenceEnabledProvider),
        user: _ref.read(currentUserProvider),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (point == null) return;

      await _ref
          .read(discoverRepositoryProvider)
          .publishPresence(
            blurredLatitude: point.latitude,
            blurredLongitude: point.longitude,
            blurRadiusMeters: point.radiusMeters.round(),
          );
    } catch (error) {
      // Присутствие — фоновая мелочь: молчим в интерфейсе, пишем в лог.
      AppLog.add('Присутствие: не удалось обновить точку: $error');
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer.cancel();
    _lifecycle.dispose();
  }
}

/// Живёт, пока открыт экран карты: ушли с него — таймер гаснет.
final presencePublisherProvider = Provider<PresencePublisher>((ref) {
  final publisher = PresencePublisher(ref);
  ref.onDispose(publisher.dispose);
  return publisher;
});
