import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/links/deep_link_service.dart';
import 'core/oauth/oauth_sign_in.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_choice.dart';

class SocialWorldApp extends ConsumerStatefulWidget {
  const SocialWorldApp({super.key});

  @override
  ConsumerState<SocialWorldApp> createState() => _SocialWorldAppState();
}

class _SocialWorldAppState extends ConsumerState<SocialWorldApp>
    with WidgetsBindingObserver {
  static final _lightTheme = AppTheme.build(AppPalette.warmSand);
  static final _darkTheme = AppTheme.build(AppPalette.burgundyChampagne);

  Timer? _scheduleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Таймер во сне телефона мог не сработать — сверяем время при возврате.
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  void _armScheduleTimer(ThemeChoice choice) {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    if (choice != ThemeChoice.schedule) return;

    final now = DateTime.now();
    _scheduleTimer = Timer(
      nextScheduleSwitch(now).difference(now) + const Duration(seconds: 1),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  void _applyPalette(AppPalette palette) {
    if (identical(palette, AppColors.current)) return;
    AppColors.current = palette;

    SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle(palette));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildWholeTree(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Подписка на редирект VK ID/Яндекс ID должна жить с самого старта —
    // иначе холодный запуск приложения по диплинку теряет первое событие.
    if (Env.isConfigured) ref.watch(oauthDeepLinkProvider);
    // Ссылки на объекты (пост, событие, место, профиль, маршрут) ловятся
    // всегда — в том числе в режиме заглушек.

    final choice = ref.watch(themeChoiceProvider);
    final palette = resolvePalette(
      choice,
      platformBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      now: DateTime.now(),
    );
    _applyPalette(palette);
    _armScheduleTimer(choice);

    final router = ref.watch(routerProvider);
    // После роутера: сервису ссылок нужен уже созданный роутер.
    ref.watch(deepLinkServiceProvider);

    return MaterialApp.router(
      title: 'ChaWo',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: palette.isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
