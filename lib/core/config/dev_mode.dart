import 'env.dart';

/// Режим разработки: быстрый вход мимо авторизации и видимый код вместо письма.
///
/// Включается сам, пока бэкенд не подключён, — то есть на всём протяжении
/// фазы 0. Принудительно: `flutter run --dart-define=DEV_MODE=true`.
/// Выключить на подключённом бэкенде: `--dart-define=DEV_MODE=false`.
abstract final class DevMode {
  static const _override = bool.fromEnvironment('DEV_MODE', defaultValue: true);

  static bool get enabled => !Env.isConfigured && _override;
}
