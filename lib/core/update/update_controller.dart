import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../debug/app_log.dart';
import 'update_info.dart';
import 'update_service.dart';

enum UpdateStage { idle, checking, upToDate, available, downloading, readyToInstall, failed }

class UpdateState {
  const UpdateState({
    this.stage = UpdateStage.idle,
    this.info,
    this.progress = 0,
    this.localPath,
    this.error,
  });

  final UpdateStage stage;
  final UpdateInfo? info;
  final double progress;
  final String? localPath;
  final String? error;

  UpdateState copyWith({
    UpdateStage? stage,
    UpdateInfo? info,
    double? progress,
    String? localPath,
    String? error,
  }) {
    return UpdateState(
      stage: stage ?? this.stage,
      info: info ?? this.info,
      progress: progress ?? this.progress,
      localPath: localPath ?? this.localPath,
      error: error ?? this.error,
    );
  }
}

/// Обновление приложения мимо Google Play: приложение раздаётся APK-файлом,
/// поэтому магазин за нас этого не сделает.
///
/// Сценарий: при входе проверяем манифест → показываем «лампочку» → человек
/// жмёт «скачать» и продолжает пользоваться приложением, пока файл качается →
/// по готовности предлагаем поставить сейчас или позже. Скачанный файл
/// переживает перезапуск, чтобы «позже» не означало «качай заново».
class UpdateController extends Notifier<UpdateState> {
  static const _prefsPathKey = 'pending_update_path';
  static const _prefsManifestKey = 'pending_update_manifest';

  late final UpdateService _service;

  @override
  UpdateState build() {
    ref.keepAlive();
    final client = http.Client();
    ref.onDispose(client.close);
    _service = UpdateService(client);
    return const UpdateState();
  }

  /// Автообновление имеет смысл только на Android: в вебе свежая версия
  /// приезжает сама, а iOS ставить APK не умеет в принципе.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> check() async {
    if (!_supported || !Env.isConfigured) return;

    final pending = await _loadPending();
    if (pending != null) {
      state = UpdateState(
        stage: UpdateStage.readyToInstall,
        info: pending.info,
        localPath: pending.path,
        progress: 1,
      );
      return;
    }

    state = const UpdateState(stage: UpdateStage.checking);
    try {
      final manifest = await _service.fetchManifest();
      if (manifest == null || manifest.versionCode <= await _currentVersionCode()) {
        state = const UpdateState(stage: UpdateStage.upToDate);
        return;
      }
      state = UpdateState(stage: UpdateStage.available, info: manifest);
    } catch (error) {
      // Нет сети или бакет недоступен — молча остаёмся без «лампочки»,
      // ронять пользователю в лицо ошибку на старте незачем.
      AppLog.add('Проверка обновления не удалась: $error');
      state = const UpdateState(stage: UpdateStage.upToDate);
    }
  }

  Future<void> download() async {
    final info = state.info;
    if (info == null) return;

    state = state.copyWith(stage: UpdateStage.downloading, progress: 0);
    try {
      final directory =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${directory.path}/social-world-${info.versionCode}.apk');

      await for (final progress in _service.downloadTo(info.apkUrl, file)) {
        state = state.copyWith(progress: progress);
      }

      await _savePending(info, file.path);
      state = state.copyWith(
        stage: UpdateStage.readyToInstall,
        localPath: file.path,
        progress: 1,
      );
    } catch (error) {
      AppLog.add('Скачивание обновления не удалось: $error');
      state = state.copyWith(
        stage: UpdateStage.failed,
        error: 'Не удалось скачать обновление. Проверьте связь и попробуйте ещё раз.',
      );
    }
  }

  /// Открывает системный установщик. Подтверждение установки показывает сама
  /// Android — обойти его нельзя, приложение не является владельцем устройства.
  /// Если человек установщик закроет, файл останется на диске и предложение
  /// повторится при следующем запуске без повторной закачки.
  Future<void> install() async {
    final path = state.localPath;
    if (path == null) return;
    await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
  }

  Future<int> _currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<({UpdateInfo info, String path})?> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefsPathKey);
    final manifest = prefs.getString(_prefsManifestKey);
    if (path == null || manifest == null) return null;

    final info = UpdateInfo.fromJson(
      jsonDecode(manifest) as Map<String, dynamic>,
    );
    final file = File(path);

    // versionCode догнал скачанный файл — значит установка прошла (или версию
    // поставили другим способом), мусор можно убирать.
    if (info.versionCode <= await _currentVersionCode() || !file.existsSync()) {
      await prefs.remove(_prefsPathKey);
      await prefs.remove(_prefsManifestKey);
      if (file.existsSync()) await file.delete();
      return null;
    }

    return (info: info, path: path);
  }

  Future<void> _savePending(UpdateInfo info, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPathKey, path);
    await prefs.setString(
      _prefsManifestKey,
      jsonEncode({
        'versionCode': info.versionCode,
        'versionName': info.versionName,
        'apkUrl': info.apkUrl,
        'notes': info.notes,
      }),
    );
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
