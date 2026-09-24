import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import 'update_controller.dart';

/// Зелёная «лампочка» — точка в правом верхнем углу [child], пока есть
/// обновление. Три места образуют цепочку «хлебных крошек»: вкладка
/// «Профиль» → шестерёнка настроек в профиле → зелёная строка «Обновления».
/// Человек идёт по зелёному и приходит к кнопке, ничего не зная заранее.
///
/// Раньше это была плавающая круглая кнопка над навигацией: её не узнавали
/// как «обновление», а на карте она ещё и налезала на карточку города.
class UpdateDot extends ConsumerWidget {
  const UpdateDot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(
      updateControllerProvider.select((state) => state.hasUpdate),
    );
    return Badge(
      isLabelVisible: visible,
      smallSize: 10,
      backgroundColor: AppColors.success,
      // Тонкая обводка цвета фона, чтобы точка не сливалась с иконкой.
      child: child,
    );
  }
}
