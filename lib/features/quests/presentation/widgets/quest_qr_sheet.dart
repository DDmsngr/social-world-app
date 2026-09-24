import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/links/deep_links.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/quest.dart';
import '../providers/quests_providers.dart';

/// QR прибытия (п. 32): организатор показывает его на месте, участник
/// наводит камеру — приложение открывается на квесте и отмечает прибытие.
/// Под QR — тот же код текстом для ручного ввода.
Future<void> showQuestQrSheet(BuildContext context, Quest quest) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: SheetCard(child: _QuestQr(quest: quest)),
    ),
  );
}

class _QuestQr extends ConsumerStatefulWidget {
  const _QuestQr({required this.quest});

  final Quest quest;

  @override
  ConsumerState<_QuestQr> createState() => _QuestQrState();
}

class _QuestQrState extends ConsumerState<_QuestQr> {
  String? _code;
  String? _error;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    _load(rotate: false);
  }

  Future<void> _load({required bool rotate}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(questsRepositoryProvider);
      final code = rotate
          ? await repo.rotateArrivalCode(widget.quest.id)
          : await repo.arrivalCode(widget.quest.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _busy = false;
      });
    } catch (error) {
      AppLog.add('Код квеста не получен: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(error, fallback: 'Не удалось получить код');
      });
    }
  }

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сменить код?'),
        content: const Text(
          'Старый QR перестанет работать. Меняйте, если фото QR разошлось '
          'по чатам и отмечаются люди, которых нет на месте.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сменить'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _load(rotate: true);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('QR прибытия'),
        const SizedBox(height: 12),
        Text(
          widget.quest.title,
          style: AppTypography.serif(24),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        if (_busy)
          const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null || code == null)
          Column(
            children: [
              Text(_error ?? 'Не удалось получить код'),
              TextButton(
                onPressed: () => _load(rotate: false),
                child: const Text('Повторить'),
              ),
            ],
          )
        else ...[
          // Белая подложка всегда: тёмный QR на тёмной теме камеры читают
          // хуже, а некоторые не читают вовсе.
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: QrImageView(
                data: DeepLinks.arrivalUri(widget.quest.id, code).toString(),
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            '${code.substring(0, 4)} ${code.substring(4)}',
            textAlign: TextAlign.center,
            style: AppTypography.serif(30),
          ),
          const SizedBox(height: 8),
          Text(
            'Покажите QR участнику: он наводит камеру телефона, и ChaWo '
            'отмечает, что он на месте. Код под QR можно ввести вручную.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _rotate, child: const Text('Сменить код')),
        ],
      ],
    );
  }
}
