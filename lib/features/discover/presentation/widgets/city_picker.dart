import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/city.dart';
import '../providers/city_provider.dart';

/// Выбор города для Pulse. Нужен там, где геолокация запрещена или человек
/// не в пилотной зоне: карта не должна пустеть и не должна зависеть от того,
/// где включён телефон (ТЗ, п. 10).
Future<void> showCityPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const Padding(
      padding: EdgeInsets.all(AppSpacing.gutter),
      child: SheetCard(child: _CityList()),
    ),
  );
}

class _CityList extends ConsumerStatefulWidget {
  const _CityList();

  @override
  ConsumerState<_CityList> createState() => _CityListState();
}

class _CityListState extends ConsumerState<_CityList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(cityProvider);
    final cities = Cities.search(_query);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Город'),
        const SizedBox(height: 14),
        TextField(
          autofocus: false,
          decoration: const InputDecoration(
            hintText: 'Найти город',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
          ),
          child: cities.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Такого города пока нет в списке',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              // Карточка листа — крашеный контейнер, а отклик на нажатие
              // ListTile рисует на ближайшем Material. Без своего Material он
              // оказался бы под подложкой и был не виден.
              : Material(
                  type: MaterialType.transparency,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: cities.length,
                    itemBuilder: (context, index) {
                      final city = cities[index];
                      final isSelected = city == selected;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(city.name),
                        subtitle: city.isPilot
                            ? const Text('Здесь уже идёт жизнь')
                            : null,
                        trailing: isSelected
                            ? Icon(Icons.check, color: AppColors.primaryTint)
                            : null,
                        onTap: () async {
                          await ref.read(cityProvider.notifier).choose(city);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
