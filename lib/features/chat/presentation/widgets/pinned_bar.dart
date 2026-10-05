import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/chat_message.dart';

/// Полоса закреплённых сообщений под шапкой чата. Нажатие ведёт к сообщению,
/// а при нескольких закрепах следующее нажатие — к следующему (как в Telegram).
/// Тот, кто может закреплять, видит справа «открепить».
class PinnedBar extends StatelessWidget {
  const PinnedBar({
    super.key,
    required this.pins,
    required this.index,
    required this.onTap,
    this.onUnpin,
  });

  /// Закрепы, свежий первым.
  final List<ChatMessage> pins;

  /// Какой закреп показан сейчас.
  final int index;
  final VoidCallback onTap;

  /// null — открепить нельзя (нет прав).
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    if (pins.isEmpty) return const SizedBox.shrink();
    final current = pins[index.clamp(0, pins.length - 1)];
    final total = pins.length;
    final position = index.clamp(0, total - 1) + 1;

    return Material(
      color: AppColors.ink2,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.hair)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              // Полоска слева разбита на столько частей, сколько закрепов:
              // подсвечена та, что показана сейчас.
              SizedBox(
                width: 3,
                height: 34,
                child: Column(
                  children: [
                    for (var i = 0; i < total; i++) ...[
                      if (i > 0) const SizedBox(height: 2),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == position - 1
                                ? AppColors.primaryTint
                                : AppColors.hairStrong,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total > 1
                          ? 'Закреплённое сообщение $position из $total'
                          : 'Закреплённое сообщение',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryTint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: AppColors.text),
                    ),
                  ],
                ),
              ),
              if (onUnpin != null)
                IconButton(
                  onPressed: onUnpin,
                  tooltip: 'Открепить',
                  icon: Icon(Icons.close, size: 20, color: AppColors.textDim),
                )
              else
                Icon(Icons.push_pin_outlined, size: 18, color: AppColors.textFaint),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
