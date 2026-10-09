import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/chat_extras_providers.dart';

/// Реакции под сообщением, как сердечко на макете «Диалог»: плашка с эмодзи
/// и числом. Моя реакция подсвечена акцентом; тап по ней — снять, по чужой —
/// поставить такую же.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.reactions,
    required this.mine,
    required this.onTap,
  });

  final List<ReactionCount> reactions;

  /// Своё сообщение — плашки прижаты вправо.
  final bool mine;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      // Без Align: он растягивался на всю ширину и раздувал пузырь.
      child: Wrap(
          alignment: mine ? WrapAlignment.end : WrapAlignment.start,
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final r in reactions)
              Semantics(
                button: true,
                label: '${r.emoji} ${r.count}${r.mine ? ', ваша реакция' : ''}',
                child: GestureDetector(
                  onTap: () => onTap(r.emoji),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: r.mine
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: r.mine ? AppColors.primaryTint : AppColors.hair,
                      ),
                    ),
                    child: Text(
                      '${r.emoji} ${r.count}',
                      style: TextStyle(
                        fontSize: 13,
                        color: r.mine ? AppColors.primaryTint : AppColors.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
      ),
    );
  }
}

/// Полоса быстрых реакций в меню сообщения.
class QuickReactionBar extends StatelessWidget {
  const QuickReactionBar({super.key, required this.current, required this.onPick});

  /// Моя текущая реакция на это сообщение.
  final String? current;
  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final emoji in quickReactions)
            Semantics(
              button: true,
              label: 'Реакция $emoji',
              child: InkResponse(
                onTap: () => onPick(emoji),
                radius: 26,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: emoji == current
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.card,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
