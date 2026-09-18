import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';

/// Вкладка «Чаты», пока личная переписка выключена (см. Features.chat).
class ChatsSoonScreen extends StatelessWidget {
  const ChatsSoonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чаты')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Скоро'),
              const SizedBox(height: 14),
              Text('Личные сообщения', style: AppTypography.serif(30)),
              const SizedBox(height: 10),
              Text(
                'Переписка появится в одном из ближайших обновлений. '
                'Пока договориться о встрече можно в обсуждении поста '
                'или события.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
