abstract final class MapkitBoot {
  /// На вебе карты нет — плагин туда не собирается.
  static String status = 'web';

  static bool get isReady => false;

  static Future<void> init(String apiKey) async {}
}
