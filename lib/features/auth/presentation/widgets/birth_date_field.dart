import 'package:flutter/material.dart';

/// Кнопка выбора даты рождения: показывает выбранную дату или приглашение.
/// Календарь открывается на 25 годах назад, чтобы не листать с сегодняшнего дня.
class BirthDateField extends StatelessWidget {
  const BirthDateField({super.key, required this.value, required this.onChanged, this.enabled = true});

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  static String format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      helpText: 'Дата рождения',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('birth-date-field'),
    onPressed: enabled ? () => _pick(context) : null,
    icon: const Icon(Icons.cake_outlined),
    label: Text(value == null ? 'Указать дату рождения' : format(value!)),
  );
}
