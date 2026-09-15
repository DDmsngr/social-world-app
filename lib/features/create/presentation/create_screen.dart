import 'package:flutter/material.dart';

import '../../../core/widgets/sw_widgets.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Создать')),
      body: const PhasePlaceholder(
        title: 'Пост или событие',
        phase: 'Фаза 1 и 3',
        items: [
          'Фото, видео, short, текст',
          'Событие с датой, местом и участниками',
          'Геометка — по желанию, размытая по умолчанию',
        ],
      ),
    );
  }
}
