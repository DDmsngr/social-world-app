import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../media/photo_viewer.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Схемы, по которым ссылка из чужого текста вообще может открыться.
/// Всё остальное (javascript:, intent:, file: и т. д.) тихо игнорируется.
const _allowedLinkSchemes = {'http', 'https', 'mailto'};

bool isSafeLink(String? href) {
  if (href == null || href.trim().isEmpty) return false;
  final uri = Uri.tryParse(href.trim());
  return uri != null && _allowedLinkSchemes.contains(uri.scheme.toLowerCase());
}

/// Безопасный показ Markdown из поста.
///
/// Flutter — не браузер: HTML и скрипты здесь не исполняются в принципе, а
/// «сырой» HTML в тексте показывается как обычные символы. Поверх этого:
/// ссылки открываются только по белому списку схем и после подтверждения (в
/// диалоге виден настоящий адрес), картинки берутся только по http(s), клик по
/// ним открывает полноэкранный просмотр.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.selectable = false});

  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge!;

    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body.copyWith(height: 1.5),
      h1: AppTypography.serif(30),
      h2: AppTypography.serif(25),
      h3: AppTypography.serif(21),
      h1Padding: const EdgeInsets.only(top: 8),
      h2Padding: const EdgeInsets.only(top: 6),
      strong: body.copyWith(fontWeight: FontWeight.w700),
      em: body.copyWith(fontStyle: FontStyle.italic),
      a: body.copyWith(
        color: AppColors.primaryTint,
        decoration: TextDecoration.underline,
      ),
      listBullet: body.copyWith(color: AppColors.primaryTint),
      blockquote: body.copyWith(color: AppColors.textDim),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.primaryTint, width: 3),
        ),
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.5,
        color: AppColors.text,
        backgroundColor: AppColors.card,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hair),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairStrong)),
      ),
    );

    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: sheet,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) => _openLink(context, href),
      imageBuilder: (uri, title, alt) => _MarkdownImage(uri: uri),
    );
  }

  Future<void> _openLink(BuildContext context, String? href) async {
    if (!isSafeLink(href)) return;
    final uri = Uri.parse(href!.trim());
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Открыть ссылку?'),
        content: Text(uri.toString(), style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
    if (go == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final url = uri.toString();
    final remote = uri.scheme == 'https' || uri.scheme == 'http';
    // Локальные пути бывают только в режиме заглушек, где нет хранилища.
    final local = !Env.isConfigured && (uri.scheme == 'blob' || uri.scheme.isEmpty);
    if (!remote && !local) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => showPhotoViewer(context, urls: [url]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: remote
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    height: 160,
                    color: AppColors.ink2,
                  ),
                  errorWidget: (_, _, _) => Container(
                    height: 90,
                    color: AppColors.ink2,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.textFaint,
                    ),
                  ),
                )
              : Image.network(url, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
