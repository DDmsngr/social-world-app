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
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
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

  // Приложение рисуется под системными панелями: фон продолжается до края
  // экрана, а отступы от панелей берутся из MediaQuery, а не из констант.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    AppTheme.overlayStyle(AppColors.current),
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
