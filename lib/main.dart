import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/mapkit_boot.dart';
import 'core/debug/app_log.dart';
import 'core/theme/theme_choice.dart';
import 'features/discover/presentation/providers/presence_publisher.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Adb недоступен на телефоне тестировщика — единственный способ увидеть
  // Dart-ошибки (не нативные, те видны только в logcat) это свой буфер,
  // открывается 5 тапами по заголовку "Рядом".
  FlutterError.onError = (details) {
    AppLog.add('FlutterError: ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.add('Uncaught: $error');
    return false;
  };

  await Env.load();
  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }

  // Ключ карты задаётся до runApp и только в Dart: в официальном плагине
  // нативной инициализации (MapKitFactory.setApiKey) больше нет.
  if (!kIsWeb) await MapkitBoot.init(Env.yandexMapkitApiKey);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final themeChoice = await loadThemeChoice();
  // Читаем до первого кадра: иначе публикатор присутствия успел бы отправить
  // точку человека, который его выключил.
  final presenceEnabled = await loadPresenceEnabled();

  FlutterNativeSplash.remove();

  runApp(
    ProviderScope(
      overrides: [
        initialThemeChoiceProvider.overrideWithValue(themeChoice),
        initialPresenceEnabledProvider.overrideWithValue(presenceEnabled),
      ],
      child: const SocialWorldApp(),
    ),
  );
}
