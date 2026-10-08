import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/debug/app_log.dart';

/// Звук нового сообщения в чате. Идентификаторы совпадают с check в миграции
/// 0057, с файлами `res/raw/<id>.wav` (каналы уведомлений) и
/// `assets/sounds/<id>.wav` (предпросмотр).
class ChatSound {
  const ChatSound(this.id, this.label);

  final String id;
  final String label;
}

const chatSounds = [
  ChatSound('ding', 'Колокольчик'),
  ChatSound('pop', 'Пузырёк'),
  ChatSound('chime', 'Мелодия'),
  ChatSound('drop', 'Капля'),
  ChatSound('knock', 'Стук'),
];

String chatSoundLabel(String? id) =>
    chatSounds.where((s) => s.id == id).firstOrNull?.label ?? 'Стандартный';

/// Короткое прослушивание при выборе звука.
abstract final class ChatSoundPreview {
  static AudioPlayer? _player;

  static Future<void> play(String id) async {
    try {
      final player = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(AssetSource('sounds/$id.wav'), volume: 0.9);
    } catch (error) {
      AppLog.add('Предпросмотр звука: $error');
    }
  }
}

/// Фон чата. Цвета тёмные и спокойные: поверх них пузыри сообщений читаются и
/// в тёмной, и в светлой теме.
class ChatWallpaper {
  const ChatWallpaper(this.id, this.label, this.colors);

  final String id;
  final String label;
  final List<Color> colors;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );
}

const chatWallpapers = [
  ChatWallpaper('sunset', 'Закат', [Color(0xFF3A1C3F), Color(0xFF8A3B4E)]),
  ChatWallpaper('night', 'Ночь', [Color(0xFF0B1226), Color(0xFF1E2A4D)]),
  ChatWallpaper('forest', 'Лес', [Color(0xFF0E2A22), Color(0xFF24503F)]),
  ChatWallpaper('ocean', 'Океан', [Color(0xFF0A2540), Color(0xFF1B6E8A)]),
  ChatWallpaper('rose', 'Роза', [Color(0xFF3B1A2B), Color(0xFF9C4A6E)]),
  ChatWallpaper('graphite', 'Графит', [Color(0xFF16181D), Color(0xFF2C313B)]),
  ChatWallpaper('sand', 'Песок', [Color(0xFF3A2F22), Color(0xFF7A6446)]),
  ChatWallpaper('aurora', 'Северное сияние', [Color(0xFF0F2A3A), Color(0xFF3E6B5E), Color(0xFF5A3F7A)]),
  ChatWallpaper('plum', 'Слива', [Color(0xFF2A1238), Color(0xFF5B2A6B)]),
  ChatWallpaper('mint', 'Мята', [Color(0xFF123A38), Color(0xFF3C8F82)]),
];

ChatWallpaper? chatWallpaperById(String? id) =>
    id == null ? null : chatWallpapers.where((w) => w.id == id).firstOrNull;

String chatWallpaperLabel(String? id) => chatWallpaperById(id)?.label ?? 'Обычный';

/// Фон под перепиской. Без выбранного — прозрачный, как раньше.
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key, required this.wallpaper, required this.child});

  final String? wallpaper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = chatWallpaperById(wallpaper);
    if (w == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: w.gradient),
      child: child,
    );
  }
}
