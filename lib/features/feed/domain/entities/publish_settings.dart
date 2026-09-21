import 'post.dart';

/// Настройки публикации: кому виден пост и раскрывается ли место.
///
/// Здесь только то, что реально существует на сервере. Новый параметр
/// добавляется полем сюда и колонкой в `posts` — пресеты и «настройки по
/// умолчанию» подхватят его через [toJson]/[fromJson] без переделки.
class PublishSettings {
  const PublishSettings({
    this.visibility = PostVisibility.everyone,
    this.showGeo = true,
  });

  static const defaults = PublishSettings();

  final PostVisibility visibility;
  final bool showGeo;

  PublishSettings copyWith({PostVisibility? visibility, bool? showGeo}) =>
      PublishSettings(
        visibility: visibility ?? this.visibility,
        showGeo: showGeo ?? this.showGeo,
      );

  /// Короткая подпись для свёрнутой карточки настроек.
  String get summary =>
      '${visibility.label} · ${showGeo ? 'с местом' : 'без места'}';

  Map<String, dynamic> toJson() => {
    'visibility': visibility.wire,
    'showGeo': showGeo,
  };

  factory PublishSettings.fromJson(Map<String, dynamic> json) =>
      PublishSettings(
        visibility: PostVisibility.parse(json['visibility']),
        showGeo: json['showGeo'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is PublishSettings &&
      other.visibility == visibility &&
      other.showGeo == showGeo;

  @override
  int get hashCode => Object.hash(visibility, showGeo);
}

/// Именованный набор настроек — «Друзья», «Без гео», «Публичный».
class PublishPreset {
  const PublishPreset({
    required this.id,
    required this.name,
    required this.settings,
  });

  final String id;
  final String name;
  final PublishSettings settings;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'settings': settings.toJson(),
  };

  factory PublishPreset.fromJson(Map<String, dynamic> json) => PublishPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    settings: PublishSettings.fromJson(
      (json['settings'] as Map).cast<String, dynamic>(),
    ),
  );
}
