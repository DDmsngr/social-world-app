import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/media_kind.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../discover/domain/entities/place.dart';

/// Выбор места чипами: общий у формы создания и у редактора поста. Повторный
/// тап по выбранному снимает выбор — «без места».
class PlacePicker extends StatelessWidget {
  const PlacePicker({
    super.key,
    required this.places,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Place> places;
  final String? selectedId;
  final ValueChanged<Place?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) {
      return Text(
        'Мест рядом пока нет.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final place in places)
          ChoiceChip(
            label: Text(place.title),
            selected: selectedId == place.id,
            onSelected: (selected) => onChanged(selected ? place : null),
            showCheckmark: false,
            backgroundColor: AppColors.card,
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              fontSize: 13,
              color: selectedId == place.id
                  ? AppColors.onPrimary
                  : AppColors.textDim,
            ),
            side: BorderSide(color: AppColors.hair),
          ),
      ],
    );
  }
}

class AttachButton extends StatelessWidget {
  const AttachButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 38),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// Превью нового вложения читается через readAsBytes: у XFile на вебе путь —
/// blob-ссылка, а на телефоне обычный файл, и это единственный способ
/// показать оба одинаково.
class AttachmentThumb extends StatelessWidget {
  const AttachmentThumb({super.key, required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _Thumb(
      onRemove: onRemove,
      child: isVideoUrl(file.path)
          ? const _VideoPlaceholder()
          : FutureBuilder(
              future: file.readAsBytes(),
              builder: (_, snapshot) => snapshot.hasData
                  ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                  : ColoredBox(color: AppColors.ink2),
            ),
    );
  }
}

/// Уже загруженное вложение при правке поста.
class ExistingMediaThumb extends StatelessWidget {
  const ExistingMediaThumb({super.key, required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _Thumb(
      onRemove: onRemove,
      child: isVideoUrl(url)
          ? const _VideoPlaceholder()
          : Image(
              image: imageProviderFor(url),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(color: AppColors.ink2),
            ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.ink2,
    child: Center(
      child: Icon(Icons.movie_outlined, color: AppColors.primaryTint),
    ),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: SizedBox(width: 92, height: 92, child: child),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 11,
              backgroundColor: AppColors.ink.withAlpha(0xCC),
              child: Icon(Icons.close, size: 13, color: AppColors.paper),
            ),
          ),
        ),
      ],
    );
  }
}
