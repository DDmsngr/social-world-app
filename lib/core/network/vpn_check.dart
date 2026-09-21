import 'dart:io';

import 'package:flutter/foundation.dart';

/// Включён ли VPN на телефоне.
///
/// Android поднимает VPN отдельным сетевым интерфейсом (tun0, ppp0, wg0…).
/// Если приложение запустили при включённом VPN и выключили его потом, сокеты
/// висят на исчезнувшей сети, и карта с сервером перестают отвечать — тогда
/// помогает перезапуск приложения.
Future<bool> isVpnActive() async {
  if (kIsWeb) return false;
  try {
    final interfaces = await NetworkInterface.list();
    return interfaces.any(
      (i) => RegExp(r'^(tun|tap|ppp|wg|ipsec|utun)\d*').hasMatch(i.name),
    );
  } catch (_) {
    return false;
  }
}
