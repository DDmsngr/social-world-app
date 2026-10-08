import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/schedule_format.dart';

/// Выбор времени для отложенной отправки: быстрые варианты сверху, три колеса
/// (день, часы, минуты) и одна кнопка, которая сразу говорит, когда уйдёт
/// сообщение. Вернёт выбранное время или null, если закрыли.
Future<DateTime?> showSchedulePicker(
  BuildContext context, {
  String title = 'Отправить позже',
  String action = 'Отправить',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.ink2,
    showDragHandle: true,
    builder: (_) => _SchedulePicker(title: title, action: action),
  );
}

const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
const _months = [
  'янв.', 'фев.', 'мар.', 'апр.', 'мая', 'июн.',
  'июл.', 'авг.', 'сен.', 'окт.', 'ноя.', 'дек.',
];

class _SchedulePicker extends StatefulWidget {
  const _SchedulePicker({required this.title, required this.action});

  final String title;
  final String action;

  @override
  State<_SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<_SchedulePicker> {
  static const _days = 366;

  late final DateTime _now = DateTime.now();
  late final DateTime _today = DateTime(_now.year, _now.month, _now.day);
  late final FixedExtentScrollController _dayWheel;
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _minuteWheel;

  var _day = 0;
  var _hour = 0;
  var _minute = 0;

  @override
  void initState() {
    super.initState();
    // По умолчанию — через час, округлив минуты до пяти вверх.
    var start = _now.add(const Duration(hours: 1));
    start = start.add(Duration(minutes: (5 - start.minute % 5) % 5));
    _day = DateTime(start.year, start.month, start.day).difference(_today).inDays;
    _hour = start.hour;
    _minute = start.minute;
    _dayWheel = FixedExtentScrollController(initialItem: _day);
    _hourWheel = FixedExtentScrollController(initialItem: _hour);
    _minuteWheel = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _dayWheel.dispose();
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  DateTime get _at => DateTime(_today.year, _today.month, _today.day + _day, _hour, _minute);

  String get _problem => validateSendAt(_at, DateTime.now()) ?? '';

  String _dayLabel(int index) {
    if (index == 0) return 'Сегодня';
    if (index == 1) return 'Завтра';
    final date = _today.add(Duration(days: index));
    final year = date.year != _today.year ? ' ${date.year}' : '';
    return '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}$year';
  }

  void _jump(DateTime at) {
    final days = DateTime(at.year, at.month, at.day).difference(_today).inDays;
    setState(() {
      _day = days.clamp(0, _days - 1);
      _hour = at.hour;
      _minute = at.minute;
    });
    const duration = Duration(milliseconds: 260);
    _dayWheel.animateToItem(_day, duration: duration, curve: Curves.easeOut);
    _hourWheel.animateToItem(_hour, duration: duration, curve: Curves.easeOut);
    _minuteWheel.animateToItem(_minute, duration: duration, curve: Curves.easeOut);
  }

  /// Быстрые варианты. Те, что уже в прошлом, не показываем.
  List<(String, DateTime)> get _presets {
    DateTime at(int plusDays, int hour) =>
        DateTime(_today.year, _today.month, _today.day + plusDays, hour);
    final untilSaturday = (DateTime.saturday - _today.weekday) % 7;
    final saturday = at(untilSaturday == 0 ? 7 : untilSaturday, 10);
    final soon = _now.add(const Duration(hours: 1));
    return [
      ('Через час', DateTime(soon.year, soon.month, soon.day, soon.hour, soon.minute)),
      if (validateSendAt(at(0, 20), _now) == null) ('Сегодня в 20:00', at(0, 20)),
      ('Завтра в 09:00', at(1, 9)),
      ('В субботу в 10:00', saturday),
    ];
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
    required int flex,
    TextAlign align = TextAlign.center,
  }) {
    return Expanded(
      flex: flex,
      child: CupertinoPicker.builder(
        scrollController: controller,
        itemExtent: 42,
        diameterRatio: 1.5,
        squeeze: 1.1,
        useMagnifier: false,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: (index) {
          onChanged(index);
        },
        childCount: count,
        itemBuilder: (context, index) => Center(
          child: Text(
            label(index),
            textAlign: align,
            style: TextStyle(
              fontSize: 19,
              color: AppColors.text,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final ok = problem.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _presets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (label, at) = _presets[index];
                  return ActionChip(
                    label: Text(label),
                    onPressed: () => _jump(at),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Подсветка выбранной строки в стиле карточек приложения.
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      border: Border.all(color: AppColors.hairStrong),
                    ),
                  ),
                  Row(
                    children: [
                      _wheel(
                        controller: _dayWheel,
                        count: _days,
                        label: _dayLabel,
                        onChanged: (i) => setState(() => _day = i),
                        flex: 5,
                      ),
                      _wheel(
                        controller: _hourWheel,
                        count: 24,
                        label: (i) => i.toString().padLeft(2, '0'),
                        onChanged: (i) => setState(() => _hour = i),
                        flex: 2,
                      ),
                      Text(':', style: TextStyle(fontSize: 19, color: AppColors.textDim)),
                      _wheel(
                        controller: _minuteWheel,
                        count: 60,
                        label: (i) => i.toString().padLeft(2, '0'),
                        onChanged: (i) => setState(() => _minute = i),
                        flex: 2,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 22,
              child: ok
                  ? null
                  : Text(problem, style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: ok ? () => Navigator.of(context).pop(_at) : null,
                child: Text('${widget.action} ${formatScheduledAt(_at, DateTime.now())}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
