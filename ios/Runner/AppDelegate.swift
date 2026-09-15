import Flutter
import UIKit
import YandexMapsMobile

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    YMKMapKit.setLocale("ru_RU")
    YMKMapKit.setApiKey(mapKitApiKey())
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func mapKitApiKey() -> String {
    let candidates = [
      Bundle.main.url(
        forResource: ".env",
        withExtension: nil,
        subdirectory: "Frameworks/App.framework/flutter_assets"
      ),
      Bundle.main.url(
        forResource: ".env",
        withExtension: nil,
        subdirectory: "flutter_assets"
      ),
    ]

    for url in candidates.compactMap({ $0 }) {
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
      for line in contents.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2,
          parts[0].trimmingCharacters(in: .whitespaces) == "YANDEX_MAPKIT_API_KEY",
          !parts[1].trimmingCharacters(in: .whitespaces).isEmpty
        {
          return parts[1].trimmingCharacters(in: .whitespaces)
        }
      }
    }

    // MapKit требует ключ до старта Flutter; при пустом .env сам виджет карты не создаётся.
    return "00000000-0000-0000-0000-000000000000"
  }
}
