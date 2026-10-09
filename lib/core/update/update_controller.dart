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
import 'update_policy.dart';
import 'update_service.dart';

enum UpdateStage {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  failed,
}

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

  /// Есть что показать человеку: новая версия найдена, качается или уже
  /// скачана и ждёт установки. От этого горят «хлебные крошки»: точка на
  /// вкладке «Профиль», точка у шестерёнки и зелёная строка в настройках.
  /// `failed` без [info] — это сбой самой проверки (нет сети), а не обновление.
  bool get hasUpdate =>
      info != null &&
      switch (stage) {
        UpdateStage.available ||
        UpdateStage.downloading ||
        UpdateStage.readyToInstall => true,
        // Скачивание сорвалось, а обновление по-прежнему есть — не гасим сигнал.
        UpdateStage.failed => true,
        _ => false,
      };

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
/// Сценарий: при входе проверяем манифест → по Wi-Fi (или по мобильной, если
/// разрешено в настройках) файл качается сам, без нажатий → по готовности
/// плашка «Обновление готово — Установить». Без подходящей сети горит
/// «лампочка», и скачать можно вручную из настроек. Скачанный файл переживает
/// перезапуск, чтобы «позже» не означало «качай заново».
class UpdateController extends Notifier<UpdateState> {
  static const _prefsPathKey = 'pending_update_path';
  static const _prefsManifestKey = 'pending_update_manifest';

  /// Сколько раз пробуем докачать, прежде чем показать ошибку.
  static const _maxDownloadAttempts = 6;

  // Не final: при повторном build на том же объекте присваивание late final
  // упало бы LateInitializationError.
  late UpdateService _service;

  DateTime? _lastCheck;

  /// Приложение могут держать открытым сутками: при возврате на экран
  /// проверяем снова, если с прошлой проверки прошло больше трёх часов, и
  /// докачиваем найденное, если появился Wi-Fi.
  Future<void> onResume() async {
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) > const Duration(hours: 3)) {
      await check();
    } else {
      await autoDownload();
    }
  }

  /// Скачивание без нажатия: найденное (или сорвавшееся) обновление качается
  /// само, если сеть подходит — Wi-Fi, а мобильная только с разрешения в
  /// настройках. Готовое предлагается поставить плашкой (UpdateReadyBanner).
  Future<void> autoDownload() async {
    final canStart = switch (state.stage) {
      UpdateStage.available => true,
      UpdateStage.failed => state.info != null,
      _ => false,
    };
    if (!canStart) return;
    final ok = UpdatePolicy.shouldAutoDownload(
      onWifi: await UpdatePolicy.onWifi(),
      allowMobile: await UpdatePolicy.allowMobile(),
    );
    if (!ok) return;
    await download();
  }

  /// Скрыта ли плашка «Обновление готово» до следующего запуска.
  bool bannerDismissed = false;

  void dismissBanner() {
    bannerDismissed = true;
    state = state.copyWith();
  }

  Future<void> _removeStaleApks({String? keep}) async {
    try {
      final directory = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final paths = directory.listSync().whereType<File>().map((f) => f.path);
      for (final path in UpdatePolicy.staleApks(paths, keep: keep)) {
        await File(path).delete();
      }
    } catch (error) {
      AppLog.add('Уборка старых APK: $error');
    }
  }

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

  /// [silent] — проверка на старте: о неудаче человеку знать незачем.
  /// Ручная проверка из настроек, наоборот, обязана сказать правду, иначе
  /// «Вы используете последнюю версию» врёт при выключенной сети.
  Future<void> check({bool silent = true}) async {
    if (!_supported || !Env.isConfigured) return;
    _lastCheck = DateTime.now();

    var pending = await _loadPending();
    await _removeStaleApks(keep: pending?.path);
    if (pending != null) {
      // Вышла версия новее скачанной — старый файл ставить незачем. Раньше
      // «готовое» обновление перекрывало проверку, и человек застревал на нём.
      try {
        final latest = await _service.fetchManifest();
        if (latest.versionCode > pending.info.versionCode) {
          await _discardPending(pending.path);
          pending = null;
        }
      } catch (_) {
        // Нет сети — остаёмся на том, что скачано.
      }
    }
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
      if (manifest.versionCode <= await _currentVersionCode()) {
        state = const UpdateState(stage: UpdateStage.upToDate);
        return;
      }
      state = UpdateState(stage: UpdateStage.available, info: manifest);
      await autoDownload();
    } catch (error) {
      AppLog.add('Проверка обновления не удалась: $error');
      state = silent
          // Нет сети или бакет недоступен — молча остаёмся без «лампочки»,
          // ронять пользователю в лицо ошибку на старте незачем.
          ? const UpdateState(stage: UpdateStage.upToDate)
          : const UpdateState(
              stage: UpdateStage.failed,
              error: 'Не удалось проверить обновления. Проверьте соединение.',
            );
    }
  }

  Future<void> download() async {
    final info = state.info;
    if (info == null) return;
    // Две закачки в один файл склеивают его в негодный: второй тап по кнопке
    // не должен начинать вторую.
    if (state.stage == UpdateStage.downloading) return;

    state = state.copyWith(stage: UpdateStage.downloading, progress: 0);
    try {
      final directory =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File(
        '${directory.path}/social-world-${info.versionCode}.apk',
      );

      final primary = info.urlFor();
      final fallback = info.fallbackUrlFor();
      var url = primary;
      // Обрыв на мобильной сети — обычное дело, а не повод сдаваться. Каждая
      // новая попытка докачивает с того места, где остановилась предыдущая
      // (см. UpdateService.downloadTo), так что повторы дёшевы.
      for (var attempt = 1; ; attempt++) {
        try {
          await for (final progress in _service.downloadTo(url, file)) {
            state = state.copyWith(progress: progress);
          }
          // Файл должен быть целым APK. Нет — стираем и качаем с нуля: докачка
          // поверх битого куска только множит битое.
          if (!UpdateService.apkLooksValid(file)) {
            if (file.existsSync()) await file.delete();
            throw Exception('Скачанный файл повреждён');
          }
          break;
        } catch (error) {
          AppLog.add(
            'Скачивание: попытка $attempt из $_maxDownloadAttempts — $error',
          );
          if (attempt >= _maxDownloadAttempts) rethrow;
          // Два захода на наш сервер, дальше — GitHub. Частичный файл с другого
          // адреса не докачиваем: начинаем заново.
          if (attempt == 2 && fallback != null && fallback != url) {
            url = fallback;
            if (file.existsSync()) await file.delete();
          }
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
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
        error:
            'Связь оборвалась. Нажмите ещё раз — файл докачается с того места, где остановился.',
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
    await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
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
    // поставили другим способом), мусор можно убирать. Битый файл тоже: его
    // установщик всё равно отвергнет.
    if (info.versionCode <= await _currentVersionCode() ||
        !file.existsSync() ||
        !UpdateService.apkLooksValid(file)) {
      await _discardPending(path);
      return null;
    }

    return (info: info, path: path);
  }

  Future<void> _discardPending(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPathKey);
    await prefs.remove(_prefsManifestKey);
    final file = File(path);
    if (file.existsSync()) await file.delete();
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
        'apkUrlArm64': info.apkUrlArm64,
        'apkUrlFallback': info.apkUrlFallback,
        'apkUrlArm64Fallback': info.apkUrlArm64Fallback,
        'notes': info.notes,
      }),
    );
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
