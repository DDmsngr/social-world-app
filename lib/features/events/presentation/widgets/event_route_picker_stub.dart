import 'package:flutter/material.dart';

import '../../../../core/widgets/state_message.dart';
import '../../domain/entities/event_route.dart';

/// Выбор точек на карте на вебе недоступен: карты там нет. Маршрут можно
/// собрать по адресам в форме создания.
class EventRoutePickerScreen extends StatelessWidget {
  const EventRoutePickerScreen({
    super.key,
    required this.initial,
    required this.centerLatitude,
    required this.centerLongitude,
  });

  final List<EventRoutePoint> initial;
  final double centerLatitude;
  final double centerLongitude;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут на карте')),
      body: const StateMessage(
        title: 'Карта доступна на Android и iOS',
        text: 'Здесь маршрут можно собрать по адресам.',
        icon: Icons.map_outlined,
      ),
    );
  }
}
