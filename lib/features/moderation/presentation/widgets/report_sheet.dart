import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/report_reason.dart';
import '../providers/report_providers.dart';

/// Возвращает true, если жалоба отправлена.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
  required String subject,
  String? authorId,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ReportSheet(
          target: target,
          targetId: targetId,
          subject: subject,
          authorId: authorId,
        ),
  );
  return sent ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.target,
    required this.targetId,
    required this.subject,
    this.authorId,
  });

  final ReportTarget target;
  final String targetId;
  final String subject;
  final String? authorId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  bool _busy = false;

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(reportRepositoryProvider)
          .submit(
            target: widget.target,
            targetId: widget.targetId,
            reason: reason,
            targetAuthorId: widget.authorId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Не удалось отправить жалобу'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.gutter,
        top: AppSpacing.gutter,
      ),
      child: SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Жалоба'),
            const SizedBox(height: 12),
            Text('Что не так?', style: AppTypography.serif(28)),
            const SizedBox(height: 8),
            Text(
              widget.subject,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (_busy) return;
                setState(() => _reason = value);
              },
              child: Column(
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: reason,
                      title: Text(
                        reason.label,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      activeColor: AppColors.primaryTint,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _reason == null || _busy ? null : _submit,
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Отправить'),
            ),
            const SizedBox(height: 6),
            Text(
              'Пока жалобу разбирают, этот контент вам больше не покажем.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
