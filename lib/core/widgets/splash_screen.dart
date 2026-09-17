import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// Android 12+ показывает системную заставку только как маленькую иконку по
// центру (платформенное ограничение SplashScreen API, полноэкранное фото
// туда не помещается) — поэтому полный hero-баннер живёт здесь, как первый
// экран самого Flutter-приложения, пока роутер разбирается с сессией.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Image.asset(
        'assets/images/splash_full.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}
