import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../providers/referrals_providers.dart';

/// Ручной ввод кода места — на случай, если ссылка из QR не открылась сама
/// (старый телефон, приложение поставили позже, код переслали текстом).
Future<void> showReferralCodeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
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
      child: const SheetCard(child: _ReferralCodeForm()),
    ),
  );
}

class _ReferralCodeForm extends ConsumerStatefulWidget {
  const _ReferralCodeForm();

  @override
  ConsumerState<_ReferralCodeForm> createState() => _ReferralCodeFormState();
}

class _ReferralCodeFormState extends ConsumerState<_ReferralCodeForm> {
  final _controller = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().length >= 4 && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(referralsRepositoryProvider).recordSignup(_controller.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Код принят, спасибо!')),
      );
    } catch (error) {
      AppLog.add('Код места не принят: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(error, fallback: 'Такой код не найден');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Код места'),
        const SizedBox(height: 12),
        Text('Ввести код с QR', style: AppTypography.serif(24)),
        const SizedBox(height: 8),
        Text(
          'Если ссылка из QR не открылась сама — впишите код, который '
          'напечатан рядом с ним.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: AppTypography.serif(24),
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
          decoration: const InputDecoration(hintText: 'ABCD23', counterText: ''),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Готово'),
        ),
      ],
    );
  }
}
