import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/local_auth_repository.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Панель разработчика на экране входа: показывает выданный код и даёт
/// проскочить авторизацию. Живёт отдельным файлом, чтобы её было легко
/// выкинуть, когда поднимется бэкенд.
class DevSignInPanel extends ConsumerWidget {
  const DevSignInPanel({super.key, this.issuedCode});

  final String? issuedCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(authRepositoryProvider);
    if (repo is! LocalAuthRepository) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.45),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.construction, size: 15, color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                'РЕЖИМ РАЗРАБОТКИ',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            issuedCode == null
                ? 'Бэкенд не подключён — письма не уходят. Код появится здесь '
                    'после запроса.'
                : 'Письмо не отправлено. Код для входа: $issuedCode',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 12.5,
                  color: AppColors.textDim,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DevButton(
                  label: 'Сразу в приложение',
                  onTap: () => repo.devSignIn(displayName: 'Алексей'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DevButton(
                  label: 'Через онбординг',
                  onTap: () => repo.devSignIn(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DevButton extends StatelessWidget {
  const _DevButton({required this.label, required this.onTap});

  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.success,
        side: BorderSide(color: AppColors.success.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
