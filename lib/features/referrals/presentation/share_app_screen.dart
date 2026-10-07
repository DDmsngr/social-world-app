import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Прямая ссылка на последнюю сборку: открыл — пошло скачивание.
/// Позже сюда встанет персональная ссылка человека (реферальная программа).
const appDownloadUrl =
    'https://api-socialworld.deepdrift.tech/updates/chawo.apk';

/// «Поделиться приложением»: ссылка для отправки и QR, который друг
/// наводит камерой телефона, не вводя ничего руками.
class ShareAppScreen extends StatelessWidget {
  const ShareAppScreen({super.key});

  static const _message = 'Заходи в ChaWo — соцсеть, которая становится городом: $appDownloadUrl';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поделиться приложением')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Зови друзей в ChaWo', style: AppTypography.serif(26)),
          const SizedBox(height: 8),
          Text(
            'Отправь ссылку или покажи QR — друг наведёт камеру и скачает приложение.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(
                data: appDownloadUrl,
                size: 240,
                backgroundColor: Colors.white,
                semanticsLabel: 'QR-код для скачивания ChaWo',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hair),
            ),
            child: SelectableText(
              appDownloadUrl,
              style: TextStyle(fontSize: 13, color: AppColors.textDim),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => SharePlus.instance.share(ShareParams(text: _message)),
            icon: const Icon(Icons.ios_share),
            label: const Text('Поделиться'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: appDownloadUrl));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Скопировать ссылку'),
          ),
        ],
      ),
    );
  }
}
