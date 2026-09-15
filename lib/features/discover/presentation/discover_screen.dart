import 'package:flutter/material.dart';

import '../../../core/widgets/sw_widgets.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Карта')),
      body: const PhasePlaceholder(
        title: 'Люди, места, пульс',
        phase: 'Фаза 2',
        items: [
          'Яндекс MapKit, люди показаны размытым районом',
          'Пульс района — где сейчас плотность выше',
          'Карточка места и поиск по карте',
        ],
      ),
    );
  }
}
