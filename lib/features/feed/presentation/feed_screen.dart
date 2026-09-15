import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sw_widgets.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сочи'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none, color: AppColors.textDim),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const PhasePlaceholder(
        title: 'Лента города',
        phase: 'Фаза 1',
        items: [
          'Посты и события людей рядом',
          'Stories тех, кто сейчас в вашем районе',
          'Кнопка «пожаловаться» на карточке с первого дня',
        ],
      ),
    );
  }
}
