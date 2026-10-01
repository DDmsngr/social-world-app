import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../debug/log_viewer_screen.dart';
import '../theme/app_colors.dart';

// Android 12+ показывает системную заставку только как маленькую иконку по
// центру (платформенное ограничение SplashScreen API, полноэкранное фото
// туда не помещается) — поэтому полный hero-баннер живёт здесь, как первый
// экран самого Flutter-приложения, пока роутер разбирается с сессией.
//
// Если сессия не определяется дольше обычного (плохая связь, сервер молчит),
// поверх баннера появляется объяснение и две кнопки: заставка без единого
// слова превращала любую неполадку в «приложение зависло».
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _patience = Duration(seconds: 8);

  Timer? _timer;
  var _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash_full.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          if (_slow)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Долго подключаемся к серверу. Проверьте интернет.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                            ),
                            onPressed: () => ref.invalidate(authStateProvider),
                            child: const Text('Повторить'),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 40),
                            ),
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                            ),
                            child: const Text('Журнал'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
