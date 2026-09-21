import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../debug/app_log.dart';

enum DevicePositionFailure { serviceOff, denied, error }

class DevicePositionResult {
  const DevicePositionResult.ok(Position this.position) : failure = null;
  const DevicePositionResult.failed(DevicePositionFailure this.failure)
    : position = null;

  /// Пользователь отказался в объясняющем окне — это не ошибка, сообщать нечего.
  const DevicePositionResult.declined()
    : position = null,
      failure = null;

  final Position? position;
  final DevicePositionFailure? failure;

  String? get message => switch (failure) {
    DevicePositionFailure.serviceOff => 'Включите геолокацию в настройках телефона',
    DevicePositionFailure.denied =>
      'Без доступа к геолокации приложение не узнает, где вы',
    DevicePositionFailure.error => 'Не удалось определить местоположение',
    null => null,
  };
}

/// Положение устройства — только для работы карты («где я», «что рядом»).
/// Это НЕ публикация: другим людям положение не уходит, у присутствия на карте
/// своя настройка. Системный запрос разрешения показывается только после
/// объяснения, зачем оно нужно.
Future<DevicePositionResult> requestDevicePosition(BuildContext context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const DevicePositionResult.failed(DevicePositionFailure.serviceOff);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (!context.mounted || !await _confirmRationale(context)) {
        return const DevicePositionResult.declined();
      }
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const DevicePositionResult.failed(DevicePositionFailure.denied);
    }

    return DevicePositionResult.ok(await Geolocator.getCurrentPosition());
  } catch (error) {
    AppLog.add('Положение устройства не определилось: $error');
    return const DevicePositionResult.failed(DevicePositionFailure.error);
  }
}

Future<bool> _confirmRationale(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Нужна геолокация телефона'),
      content: const Text(
        'Она нужна, чтобы найти вас на карте и показать, что рядом. '
        'Другим людям ваше положение при этом не публикуется — это отдельная '
        'настройка в профиле.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Не сейчас'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Продолжить'),
        ),
      ],
    ),
  );
  return go ?? false;
}
