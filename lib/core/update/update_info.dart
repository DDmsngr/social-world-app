/// Описание доступного обновления из `manifest.json` в бакете `app-releases`.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.notes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: json['versionCode'] as int,
      versionName: json['versionName'] as String? ?? '',
      apkUrl: json['apkUrl'] as String,
      notes: json['notes'] as String? ?? '',
    );
  }

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String notes;
}
