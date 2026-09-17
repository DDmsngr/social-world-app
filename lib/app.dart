import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/oauth/oauth_sign_in.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class SocialWorldApp extends ConsumerWidget {
  const SocialWorldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Подписка на редирект VK ID/Яндекс ID должна жить с самого старта —
    // иначе холодный запуск приложения по диплинку теряет первое событие.
    if (Env.isConfigured) ref.watch(oauthDeepLinkProvider);

    return MaterialApp.router(
      title: 'Social World',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
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
