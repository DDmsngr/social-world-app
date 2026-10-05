import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/debug/app_log.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/sw_widgets.dart';
import '../feed/domain/entities/post.dart';
import '../feed/domain/entities/publish_settings.dart';
import '../feed/presentation/providers/feed_providers.dart';
import 'archive_reader.dart';
import 'instagram_archive.dart';

const _exportPage = 'https://accountscenter.instagram.com/info_and_permissions/dyi/';

enum _Step { intro, reading, preview, importing, done }

/// Профиль → Импорт из запрещённограмма. Человек выбирает zip с выгрузкой своих
/// данных, приложение читает его на телефоне и переносит публикации в ленту.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  var _step = _Step.intro;
  DataArchive? _archive;
  String? _zipPath;
  var _selected = <int>{};
  var _visibility = PostVisibility.everyone;

  var _done = 0;
  var _failed = 0;
  var _cancel = false;
  String? _error;

  ParsedExport get _data => _archive!.parsed;

  @override
  void dispose() {
    _archive?.close();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = file?.path;
    if (path == null) return;

    setState(() {
      _step = _Step.reading;
      _error = null;
    });
    try {
      await _archive?.close();
      // Ник берём из имени файла выгрузки: у копии из кэша оно сохраняется.
      final archive = await DataArchive.open(path);
      if (!mounted) {
        await archive.close();
        return;
      }
      _zipPath = path;
      _archive = archive;
      _selected = {for (var i = 0; i < archive.parsed.posts.length; i++) i};
      setState(() => _step = _Step.preview);
    } catch (error) {
      AppLog.add('Архив не открылся: $error');
      if (!mounted) return;
      setState(() {
        _step = _Step.intro;
        _error = 'Не получилось открыть файл. Нужен zip, который прислала '
            'прежняя сеть, в формате JSON.';
      });
    }
  }

  Future<void> _import() async {
    final archive = _archive;
    if (archive == null) return;
    final repo = ref.read(feedRepositoryProvider);
    final temp = await getTemporaryDirectory();
    final dir = await Directory('${temp.path}/import').create(recursive: true);

    setState(() {
      _step = _Step.importing;
      _done = 0;
      _failed = 0;
      _cancel = false;
    });

    final picked = [for (final i in _selected.toList()..sort()) _data.posts[i]];
    for (final post in picked) {
      if (_cancel || !mounted) break;
      final files = <String>[];
      try {
        for (final m in post.media.take(maxMediaPerPost)) {
          final path = await archive.extract(m.entry, dir, '${files.length}_${DateTime.now().microsecondsSinceEpoch}');
          if (path != null) files.add(path);
        }
        final long = post.caption.length > maxMomentCaption;
        await repo.createPost(
          body: post.caption,
          postType: long ? PostType.article : PostType.moment,
          title: long ? articleTitle(post.caption) : null,
          bodyFormat: long ? BodyFormat.markdown : BodyFormat.plain,
          settings: PublishSettings(visibility: _visibility, showGeo: false),
          mediaPaths: files,
          createdAt: post.takenAt,
        );
        if (mounted) setState(() => _done++);
      } catch (error) {
        AppLog.add('Публикация не перенеслась: $error');
        if (mounted) {
          setState(() {
            _failed++;
            _error = friendlyError(error, fallback: 'Часть публикаций не перенеслась');
          });
        }
      } finally {
        for (final f in files) {
          try {
            await File(f).delete();
          } catch (_) {}
        }
      }
    }

    ref.invalidate(feedProvider);
    ref.invalidate(myPostsProvider);
    if (mounted) setState(() => _step = _Step.done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Импорт из запрещённограмма'),
        leading: IconButton(
          onPressed: _step == _Step.importing
              ? null
              : () => context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: switch (_step) {
        _Step.intro => _Intro(onPick: _pick, error: _error),
        _Step.reading => const Center(child: CircularProgressIndicator()),
        _Step.preview => _preview(context),
        _Step.importing => _progress(context),
        _Step.done => _finished(context),
      },
    );
  }

  Widget _preview(BuildContext context) {
    final theme = Theme.of(context);
    final posts = _data.posts;
    final skipped = posts.where((p) => p.media.length > maxMediaPerPost).length;

    return ListView(
      padding: AppSpacing.page(context),
      children: [
        Text(
          posts.isEmpty
              ? 'В этом архиве нет публикаций'
              : 'Нашли ${posts.length} ${_posts(posts.length)}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          posts.isEmpty
              ? 'Проверьте, что при выгрузке отмечены «Публикации».'
              : 'Подписи и даты сохранятся. Из каждой публикации возьмём до '
                    '$maxMediaPerPost фото и видео'
                    '${skipped > 0 ? ' (у $skipped их больше)' : ''}.',
          style: theme.textTheme.bodyMedium,
        ),
        if (posts.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('Кому показывать'),
          const SizedBox(height: 10),
          SegmentedButton<PostVisibility>(
            showSelectedIcon: false,
            segments: [
              for (final v in PostVisibility.values)
                ButtonSegment(value: v, label: Text(v.label, style: const TextStyle(fontSize: 13))),
            ],
            selected: {_visibility},
            onSelectionChanged: (s) => setState(() => _visibility = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            'Старые публикации встанут в ленту по исходным датам. «Только мне» — '
            'чтобы сначала проверить, как всё перенеслось.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textFaint),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: SectionLabel('Что переносим: ${_selected.length}')),
              TextButton(
                onPressed: () => setState(() {
                  _selected = _selected.length == posts.length
                      ? <int>{}
                      : {for (var i = 0; i < posts.length; i++) i};
                }),
                child: Text(_selected.length == posts.length ? 'Снять все' : 'Выбрать все'),
              ),
            ],
          ),
          for (var i = 0; i < posts.length; i++)
            CheckboxListTile(
              value: _selected.contains(i),
              onChanged: (on) => setState(() => on == true ? _selected.add(i) : _selected.remove(i)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                posts[i].caption.isEmpty ? 'Без подписи' : posts[i].caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (posts[i].takenAt != null) _date(posts[i].takenAt!),
                  '${posts[i].media.length} ${_files(posts[i].media.length)}',
                ].join(' · '),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _selected.isEmpty ? null : _import,
            child: Text('Перенести ${_selected.length}'),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _pick, child: const Text('Выбрать другой архив')),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final total = _selected.length;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Переносим: ${_done + _failed} из $total', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: total == 0 ? null : (_done + _failed) / total,
              color: AppColors.primary,
              backgroundColor: AppColors.hair,
            ),
            const SizedBox(height: 12),
            Text(
              'Не закрывайте приложение, пока идёт перенос.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _cancel ? null : () => setState(() => _cancel = true),
              child: Text(_cancel ? 'Останавливаем…' : 'Остановить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _finished(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            Text('Перенесли: $_done', style: theme.textTheme.titleLarge),
            if (_failed > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Не получилось: $_failed. ${_error ?? ''}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final path = _zipPath;
                if (path != null && path.contains('file_picker')) {
                  // Копию архива из кэша выбора файла больше хранить незачем.
                  try {
                    await _archive?.close();
                    await File(path).delete();
                  } catch (_) {}
                }
                if (!context.mounted) return;
                context.canPop() ? context.pop() : context.go(Routes.profile);
              },
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }
}

String _posts(int n) {
  final r = n % 100;
  if (r >= 11 && r <= 14) return 'публикаций';
  return switch (n % 10) {
    1 => 'публикацию',
    2 || 3 || 4 => 'публикации',
    _ => 'публикаций',
  };
}

String _files(int n) => n == 1 ? 'файл' : (n >= 2 && n <= 4 ? 'файла' : 'файлов');

String _date(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${two(l.day)}.${two(l.month)}.${l.year}';
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick, this.error});

  final VoidCallback onPick;
  final String? error;

  static const _steps = [
    'Откройте страницу выгрузки данных (кнопка ниже). Понадобится войти в '
        'аккаунт, в России может потребоваться VPN.',
    'Выберите «Скачать или перенести информацию», свой профиль и «Часть '
        'информации». Отметьте публикации, ролики, подписчиков и подписки.',
    'Способ — «Скачать на устройство». Период — «Всё время», формат — JSON.',
    'Нажмите «Создать файлы». Архив придёт на почту: от пары минут до пары '
        'дней. Скачайте его на телефон.',
    'Вернитесь сюда и выберите этот файл. Остальное приложение сделает само.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: AppSpacing.page(context),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF)],
                ),
              ),
              child: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Переезжайте вместе с постами и фото',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Файл с вашими данными не уходит на сервер целиком: приложение читает '
          'его у вас на телефоне и отправляет только те публикации, которые '
          'вы выберете.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        const SectionLabel('Как получить файл'),
        const SizedBox(height: 10),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                  child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(_steps[i], style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        Text(
          'Названия пунктов в настройках иногда меняются, смысл тот же.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textFaint),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(_exportPage), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Открыть страницу выгрузки'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open),
          label: const Text('Выбрать файл с данными'),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
