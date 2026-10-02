import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Шапка карточки объекта на карте: красная метка типа («КВЕСТ», «СОБЫТИЕ»,
/// «МЕСТО») и справа от неё время или категория. Одинаковая у всех карточек,
/// чтобы с первого взгляда было ясно, что это за объект.
class SheetKindHeader extends StatelessWidget {
  const SheetKindHeader({super.key, required this.kind, this.detail});

  final String kind;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            kind.toUpperCase(),
            style: TextStyle(
              color: AppColors.onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}

/// Строка факта: значок и текст («место», «участники», «до вас 300 м»).
class SheetFact extends StatelessWidget {
  const SheetFact({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textDim),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}

/// «Подробнее →» — ссылка под описанием, а не внизу за кнопками.
class SheetMoreLink extends StatelessWidget {
  const SheetMoreLink({super.key, required this.onPressed, this.label = 'Подробнее →'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}
