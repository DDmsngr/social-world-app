import 'package:flutter/material.dart';

/// Полупрозрачная плашка с днём («Сегодня», «7 октября»): между сообщениями и
/// плавающая сверху, пока листают ленту.
class DayChip extends StatelessWidget {
  const DayChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
