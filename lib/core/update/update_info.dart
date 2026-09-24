import 'dart:io';

/// Описание доступного обновления из `manifest.json` в бакете `app-releases`.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.notes,
    this.apkUrlArm64,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: json['versionCode'] as int,
      versionName: json['versionName'] as String? ?? '',
      apkUrl: json['apkUrl'] as String,
      notes: json['notes'] as String? ?? '',
      // Необязательное поле: старые манифесты его не знают.
      apkUrlArm64: json['apkUrlArm64'] as String?,
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
