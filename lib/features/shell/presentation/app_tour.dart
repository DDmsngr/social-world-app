import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Проводник по вкладкам после знакомства: человек сразу видит, что где,
/// а не открывает карту и не гадает, что с ней делать.
abstract final class AppTour {
  static const _key = 'app_tour_pending';

  /// Ставит проводник в очередь: его покажет оболочка вкладок.
  static Future<void> markPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Забирает отметку: проводник показывается один раз.
  static Future<bool> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_key) ?? false;
    if (pending) await prefs.remove(_key);
    return pending;
  }

  static const steps = <TourStep>[
    TourStep(
      // Приветствие показываем на Pulse — главной вкладке: если приложение
      // открыто ярлыком чата, проводник не должен висеть поверх переписки.
      tab: 1,
      icon: Icons.waving_hand_outlined,
      title: 'Добро пожаловать в ChaWo',
      text: 'Это лента, карта города и мессенджер в одном приложении. '
          'Покажем за минуту, что где.',
    ),
    TourStep(
      tab: 0,
      icon: Icons.photo_library_outlined,
      title: 'Flow — лента',
      text: 'Посты, фото и блики людей. Листайте, ставьте лайки, '
          'комментируйте, подписывайтесь на интересных людей.',
    ),
    TourStep(
      tab: 1,
      icon: Icons.map_outlined,
      title: 'Pulse — карта города',
      text: 'Что происходит рядом: события, места, квесты и просьбы «Мне надо». '
          'Яркие пятна — там, где сейчас активно. Город меняется вверху экрана.',
    ),
    TourStep(
      tab: 2,
      icon: Icons.add_circle_outline,
      title: 'Создать',
      text: 'Пост, блик, событие или маршрут — всё публикуется отсюда.',
    ),
    TourStep(
      tab: 3,
      icon: Icons.forum_outlined,
      title: 'Чаты',
      text: 'Личные и групповые переписки, звонки и каналы. Личные чаты '
          'зашифрованы: прочитать их можете только вы и собеседник.',
    ),
    TourStep(
      tab: 4,
      icon: Icons.person_outline,
      title: 'Профиль',
      text: 'Ваша страница, @ник, по которому вас найдут без номера телефона, '
          'настройки и приглашения друзей.',
    ),
  ];
}

class TourStep {
  const TourStep({
    required this.tab,
    required this.icon,
    required this.title,
    required this.text,
  });

  /// Вкладка, которую показываем на этом шаге; null — без переключения.
  final int? tab;
  final IconData icon;
  final String title;
  final String text;
}

/// Карточка проводника поверх вкладок: затемнение и подсказка над нижней
/// панелью, чтобы была видна вкладка, о которой речь.
class AppTourOverlay extends StatelessWidget {
  const AppTourOverlay({
    super.key,
    required this.step,
    required this.onNext,
    required this.onClose,
  });

  final int step;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final item = AppTour.steps[step];
    final last = step == AppTour.steps.length - 1;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onNext,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: bottom + 86,
          child: Material(
            color: AppColors.ink2,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(item.icon, color: AppColors.primaryTint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item.title, style: AppTypography.serif(22)),
                      ),
                      Text(
                        '${step + 1}/${AppTour.steps.length}',
                        style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(item.text, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (!last)
                        TextButton(onPressed: onClose, child: const Text('Пропустить')),
                      const Spacer(),
                      FilledButton(
                        style: AppButtons.compact,
                        onPressed: last ? onClose : onNext,
                        child: Text(last ? 'Начать' : 'Дальше'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
