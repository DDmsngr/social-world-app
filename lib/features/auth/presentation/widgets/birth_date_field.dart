import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Поле даты рождения: набираешь цифры, точки встают сами (ДД.ММ.ГГГГ).
/// Справа — календарь для тех, кому удобнее выбрать. [onChanged] получает
/// дату, когда она набрана целиком и настоящая, иначе null.
class BirthDateField extends StatefulWidget {
  const BirthDateField({super.key, required this.value, required this.onChanged, this.enabled = true});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;

  static String format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  /// Дата из «ДД.ММ.ГГГГ»; null — набрано не до конца, такой даты нет или она
  /// в будущем / раньше чем 110 лет назад.
  static DateTime? parse(String text, {DateTime? now}) {
    final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
    if (match == null) return null;
    final day = int.parse(match[1]!), month = int.parse(match[2]!), year = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year) return null;
    final today = now ?? DateTime.now();
    if (date.isAfter(today) || year < today.year - 110) return null;
    return date;
  }

  @override
  State<BirthDateField> createState() => _BirthDateFieldState();
}

class _BirthDateFieldState extends State<BirthDateField> {
  late final _controller = TextEditingController(
    text: widget.value == null ? '' : BirthDateField.format(widget.value!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _error {
    final text = _controller.text;
    if (text.length < 10) return null;
    return BirthDateField.parse(text) == null ? 'Такой даты нет' : null;
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      helpText: 'Дата рождения',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    if (picked == null || !mounted) return;
    setState(() => _controller.text = BirthDateField.format(picked));
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('birth-date-field'),
    controller: _controller,
    enabled: widget.enabled,
    keyboardType: TextInputType.number,
    inputFormatters: const [_DateDotsFormatter()],
    decoration: InputDecoration(
      labelText: 'Дата рождения',
      hintText: 'ДД.ММ.ГГГГ',
      errorText: _error,
      suffixIcon: IconButton(
        tooltip: 'Выбрать в календаре',
        icon: const Icon(Icons.calendar_month_outlined),
        onPressed: widget.enabled ? _pick : null,
      ),
    ),
    onChanged: (text) {
      setState(() {});
      widget.onChanged(BirthDateField.parse(text));
    },
  );
}

/// Цифры → «ДД.ММ.ГГГГ»: всё, кроме цифр, отбрасывается, точка после второй
/// и четвёртой цифры, не больше восьми цифр. Курсор — в конце: дату набирают подряд.
class _DateDotsFormatter extends TextInputFormatter {
  const _DateDotsFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String digitsOf(String s) => s.replaceAll(RegExp(r'\D'), '');
    var digits = digitsOf(newValue.text);
    // Стёрли точку — стираем и цифру перед ней, иначе точка вставала бы обратно.
    if (newValue.text.length < oldValue.text.length && digits == digitsOf(oldValue.text) && digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    if (digits.length > 8) digits = digits.substring(0, 8);
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) out.write('.');
      out.write(digits[i]);
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
