import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/quest.dart';

/// Ввод кода прибытия руками — на случай, если камера не открыла ссылку из
/// QR (старый телефон, камера без распознавания ссылок). Код напечатан под
/// QR у организатора. Возвращает введённый код или `null`.
Future<String?> showArrivalCodeSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const SheetCard(child: _ArrivalCodeForm()),
    ),
  );
}

class _ArrivalCodeForm extends StatefulWidget {
  const _ArrivalCodeForm();

  @override
  State<_ArrivalCodeForm> createState() => _ArrivalCodeFormState();
}

class _ArrivalCodeFormState extends State<_ArrivalCodeForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => normalizeArrivalCode(_controller.text).length == 8;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(normalizeArrivalCode(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Я на месте'),
        const SizedBox(height: 12),
        Text('Код с QR', style: AppTypography.serif(26)),
        const SizedBox(height: 8),
        Text(
          'Наведите камеру телефона на QR у организатора — приложение '
          'откроется само. Не получилось? Введите 8 символов под QR.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: AppTypography.serif(26),
          maxLength: 9,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 -]')),
          ],
          decoration: const InputDecoration(hintText: 'ABCD 2345', counterText: ''),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Отметиться'),
        ),
      ],
    );
  }
}
