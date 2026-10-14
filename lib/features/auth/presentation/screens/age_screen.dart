import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../providers/auth_providers.dart';
import '../widgets/birth_date_field.dart';

/// Возраст нужен всем: от него зависит, что мы показываем (стикеры 18+).
/// Спрашиваем один раз; у тех, кто регистрировался раньше, этот экран
/// появляется при следующем входе.
class AgeScreen extends ConsumerStatefulWidget {
  const AgeScreen({super.key});

  @override
  ConsumerState<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends ConsumerState<AgeScreen> {
  DateTime? _date;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final date = _date;
    if (date == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).setBirthDate(date);
    } catch (e) {
      AppLog.add('Дата рождения не сохранилась: $e');
      if (mounted) setState(() => _error = 'Не получилось сохранить. Проверьте связь и повторите.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const SectionLabel('Возраст'),
              const SizedBox(height: 14),
              Text('Сколько вам лет?', style: AppTypography.serif(36)),
              const SizedBox(height: 16),
              Text(
                'Часть стикеров только для взрослых. Дату увидите только вы, '
                'другим она не показывается. Изменить её потом нельзя, поэтому укажите настоящую.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              BirthDateField(value: _date, enabled: !_busy, onChanged: (d) => setState(() => _date = d)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                key: const Key('age-save'),
                onPressed: _date == null || _busy ? null : _save,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('Продолжить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
