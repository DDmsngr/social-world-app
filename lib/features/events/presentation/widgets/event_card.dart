import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/event.dart';

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.onToggleJoin,
    required this.onReport,
    this.onTap,
  });

  final Event event;
  final VoidCallback onToggleJoin;
  final VoidCallback onReport;

  /// Открывает карточку события. Кнопки внутри (участвовать/пожаловаться)
  /// гасят тап сами через свои onPressed — до InkWell он не долетает.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: AppColors.card,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatWhen(event.startsAt),
                            style: AppTypography.serif(
                              15,
                              color: AppColors.primaryTint,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onReport,
                      tooltip: 'Пожаловаться',
                      icon: const Icon(
                        Icons.flag_outlined,
                        size: 19,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
                if (event.description != null &&
                    event.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    event.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 16,
                      color: AppColors.textFaint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Организатор: ${event.authorName}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                    if (event.placeTitle != null) ...[
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: AppColors.textFaint,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.placeTitle!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onToggleJoin,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: event.joinedByMe
                              ? AppColors.onPrimary
                              : AppColors.primaryTint,
                          backgroundColor: event.joinedByMe
                              ? AppColors.primary
                              : Colors.transparent,
                        ),
                        child: Text(
                          event.joinedByMe ? 'Вы участвуете' : 'Участвовать',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${event.participantCount} идёт',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatWhen(DateTime time) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '${time.day} ${months[time.month - 1]}, $hh:$mm';
}
