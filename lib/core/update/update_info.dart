import 'dart:io';

/// Описание доступного обновления из `manifest.json` в DDmsngr/social-world-releases.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.notes,
    this.apkUrlArm64,
    this.apkUrlFallback,
    this.apkUrlArm64Fallback,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: json['versionCode'] as int,
      versionName: json['versionName'] as String? ?? '',
      apkUrl: json['apkUrl'] as String,
      notes: json['notes'] as String? ?? '',
      // Необязательное поле: старые манифесты его не знают.
      apkUrlArm64: json['apkUrlArm64'] as String?,
      apkUrlFallback: json['apkUrlFallback'] as String?,
      apkUrlArm64Fallback: json['apkUrlArm64Fallback'] as String?,
    );
  }

  final int versionCode;
  final String versionName;

  /// Универсальный APK — для любого телефона, но тяжёлый (все архитектуры).
  final String apkUrl;

  /// Лёгкий APK только для arm64 (~70 МБ вместо ~175). У почти всех
  /// нынешних телефонов именно эта архитектура, а на мобильной сети
  /// файл втрое меньшего размера доходит заметно чаще.
  final String? apkUrlArm64;
  final String notes;

  /// Те же файлы на GitHub: запасной путь, если наш сервер недоступен.
  final String? apkUrlFallback;
  final String? apkUrlArm64Fallback;

  /// Запасная ссылка на тот же файл, что и [urlFor]. null — запасной нет.
  String? fallbackUrlFor({String? platformVersion}) {
    final arm64 = apkUrlArm64;
    if (arm64 == null) return apkUrlFallback;
    final version = platformVersion ?? Platform.version;
    return version.contains('android_arm64') ? apkUrlArm64Fallback : apkUrlFallback;
  }

  /// Какой файл качать этому телефону. Архитектуру берём из строки версии
  /// Dart (`... on "android_arm64"`) — отдельный пакет ради этого не нужен.
  /// Не уверены — качаем универсальный: он подходит всем.
  String urlFor({String? platformVersion}) {
    final arm64 = apkUrlArm64;
    if (arm64 == null) return apkUrl;
    final version = platformVersion ?? Platform.version;
    return version.contains('android_arm64') ? arm64 : apkUrl;
  }
}
