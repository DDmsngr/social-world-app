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

enum _Step { intro, copying, reading, preview, importing, done }

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

  /// Выбранные части выгрузки: путь к копии и «имя|размер» — по нему
  /// узнаём, что ту же часть выбрали второй раз.
  final _zips = <({String path, String key})>[];
  var _selected = <int>{};

  /// Публикации, которые уже есть в ленте (перенесены раньше).
  var _already = <int>{};

  /// Публикации, часть файлов которых лежит в ещё не добавленной части.
  var _missing = 0;
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

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Выбор одной или нескольких частей выгрузки. [add] — добавить к уже
  /// выбранным, иначе начать заново.
  Future<void> _pick({bool add = false}) async {
    final previous = _step;
    final List<PlatformFile> files;
    try {
      // Телефон сначала копирует архив к себе — у гигабайтного это минуты.
      // Без экрана ожидания казалось, что приложение ничего не делает.
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        onFileLoading: (status) {
          if (!mounted) return;
          if (status == FilePickerStatus.picking) {
            setState(() => _step = _Step.copying);
          }
        },
      );
    } catch (error) {
      AppLog.add('Выбор архива: $error');
      if (mounted) setState(() => _step = previous);
      return;
    }
    if (!mounted) return;
    if (files.isEmpty) {
      setState(() => _step = previous);
      return;
    }

    final kept = add ? [..._zips] : <({String path, String key})>[];
    var repeats = 0;
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      final key = '${file.name}|${file.lengthSync() ?? await file.length()}';
      if (kept.any((z) => z.key == key)) {
        repeats++;
        continue;
      }
      kept.add((path: path, key: key));
    }
    if (repeats > 0) {
      _toast(repeats == 1 ? 'Эта часть уже добавлена' : 'Повторные части пропущены');
    }
    if (add && kept.length == _zips.length) {
      setState(() => _step = previous);
      return;
    }
    await _open(kept, fallback: previous);
  }

  Future<void> _open(
    List<({String path, String key})> zips, {
    required _Step fallback,
  }) async {
    setState(() {
      _step = _Step.reading;
      _error = null;
    });
    try {
      await _archive?.close();
      _archive = null;
      final archive = await DataArchive.open([for (final z in zips) z.path]);
      final already = await _alreadyImported(archive.parsed.posts);
      if (!mounted) {
        await archive.close();
        return;
      }
      final posts = archive.parsed.posts;
      _zips
        ..clear()
        ..addAll(zips);
      _archive = archive;
      _already = already;
      _missing = posts.where((p) => p.media.any((m) => !archive.has(m.entry))).length;
      _selected = {
        for (var i = 0; i < posts.length; i++)
          if (!already.contains(i)) i,
      };
      setState(() => _step = _Step.preview);
    } catch (error) {
      AppLog.add('Архив не открылся: $error');
      if (!mounted) return;
      setState(() {
        _step = fallback == _Step.preview ? _Step.intro : fallback;
        _error = 'Не получилось открыть файл. Нужен zip, который прислала '
            'прежняя сеть, в формате JSON.';
      });
    }
  }

  /// Какие публикации уже переносили: у перенесённой дата совпадает с
  /// исходной до секунды. Повторный выбор того же архива их не задвоит.
  Future<Set<int>> _alreadyImported(List<ImportedPost> posts) async {
    try {
      final mine = await ref.read(myPostsProvider.future);
      final dates = {
        for (final p in mine) p.createdAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      };
      return {
        for (var i = 0; i < posts.length; i++)
          if (posts[i].takenAt case final t?
              when dates.contains(t.toUtc().millisecondsSinceEpoch ~/ 1000))
            i,
      };
    } catch (error) {
      AppLog.add('Не проверили, что уже перенесено: $error');
      return {};
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
        _Step.copying => const _Waiting(
          title: 'Копируем архив на телефон',
          text: 'Архив на несколько гигабайт копируется несколько минут. '
              'Не закрывайте приложение и не выключайте экран.',
        ),
        _Step.reading => const _Waiting(
          title: 'Читаем архив',
          text: 'Ищем публикации, фото и видео. Обычно это меньше минуты.',
        ),
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
              ? 'Проверьте, что при выгрузке отмечены «Публикации». Если '
                    'выгрузка пришла несколькими файлами, добавьте остальные '
                    'части — публикации могут лежать в другой.'
              : 'Подписи и даты сохранятся. Из каждой публикации возьмём до '
                    '$maxMediaPerPost фото и видео'
                    '${skipped > 0 ? ' (у $skipped их больше)' : ''}.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _PartsCard(
          parts: _zips.length,
          missing: _missing,
          already: _already.length,
          onAdd: () => _pick(add: true),
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
                  if (_already.contains(i)) 'уже перенесено',
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
        OutlinedButton(onPressed: _pick, child: const Text('Начать с другим архивом')),
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
                // Копии архива в кэше выбора файла (это гигабайты) больше
                // хранить незачем.
                try {
                  await _archive?.close();
                  _archive = null;
                } catch (_) {}
                for (final zip in _zips) {
                  if (!zip.path.contains('file_picker')) continue;
                  try {
                    await File(zip.path).delete();
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

class _Waiting extends StatelessWidget {
  const _Waiting({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            LinearProgressIndicator(color: AppColors.primary, backgroundColor: AppColors.hair),
            const SizedBox(height: 12),
            Text(text, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Сколько частей выгрузки выбрано и чего не хватает.
class _PartsCard extends StatelessWidget {
  const _PartsCard({
    required this.parts,
    required this.missing,
    required this.already,
    required this.onAdd,
  });

  final int parts;
  final int missing;
  final int already;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [
      'Частей архива: $parts',
      if (missing > 0)
        'У $missing ${_posts(missing)} фото или видео лежат в другой части — '
            'добавьте её, иначе они перенесутся без этих файлов',
      if (already > 0)
        '$already ${_posts(already)} уже есть в ленте — их не отмечаем, '
            'чтобы не задвоить',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: missing > 0 ? AppColors.primary : AppColors.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить часть архива'),
          ),
        ],
      ),
    );
  }
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
    'Вернитесь сюда и выберите этот файл. Если выгрузка пришла несколькими '
        'файлами, отметьте их все сразу или добавьте по одному. Остальное '
        'приложение сделает само.',
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
