import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../chat/presentation/widgets/video_note_recorder.dart';
import '../../feed/presentation/providers/feed_providers.dart';
import 'avatar_crop_screen.dart';
import 'providers/profile_providers.dart';

/// Видеоаватар: у премиума — записать кружок до 8 секунд или убрать, у
/// остальных — замок «в Премиуме». Показывается только при включённом флаге
/// `Features.videoAvatar`; решение «можно ли» принимает сервер.
class _VideoAvatarTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VideoAvatarTile> createState() => _VideoAvatarTileState();
}

class _VideoAvatarTileState extends ConsumerState<_VideoAvatarTile> {
  bool? _premium;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(profileRepositoryProvider).isPremium().then(
      (value) {
        if (mounted) setState(() => _premium = value);
      },
      onError: (Object _) {
        if (mounted) setState(() => _premium = false);
      },
    );
  }

  Future<void> _record() async {
    final result = await Navigator.of(context, rootNavigator: true).push<VideoNoteResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const VideoNoteRecorderScreen(maxDuration: Duration(seconds: 8)),
      ),
    );
    if (result == null || !mounted) return;
    await _apply(result.path);
  }

  Future<void> _apply(String? path) async {
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).setAvatarVideo(path);
      final me = ref.read(currentUserProvider);
      if (me != null) ref.invalidate(userProfileProvider(me.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? 'Видеоаватар убран' : 'Видеоаватар сохранён')),
      );
    } catch (error) {
      AppLog.add('Видеоаватар: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось сохранить видеоаватар'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = _premium;
    if (premium == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: premium
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _record,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('Видеоаватар'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _apply(null),
                  child: const Text('Убрать'),
                ),
              ],
            )
          : Center(
              child: Text(
                'Видеоаватар — в Премиуме',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
    );
  }
}

/// Правка собственной анкеты: имя, город, о себе, аватар. Записывается в
/// профиль на сервере (а не только на устройстве) и приходит обратно в
/// сессию, поэтому после перезапуска видны те же данные.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _bio;
  final _picker = ImagePicker();

  XFile? _newAvatar;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final me = ref.read(currentUserProvider);
    _name = TextEditingController(text: me?.displayName ?? '');
    _city = TextEditingController(text: me?.city ?? '');
    _bio = TextEditingController(text: me?.bio ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().length >= 2;

  Future<void> _pickAvatar(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      // Аватар показывается кружком в десятки пикселей: полноразмерное фото
      // только тратит трафик.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    // Сразу после выбора — настройка кадра: человек видит, как фото ляжет в
    // кружок, и двигает его. Закрыл экран — оставляем выбранное как есть.
    final framed = await openAvatarCrop(context, source: file.path);
    if (!mounted) return;
    setState(() => _newAvatar = XFile(framed ?? file.path));
  }

  /// Подвинуть фото в кружке: текущий аватар или только что выбранный.
  Future<void> _adjustAvatar(String source) async {
    final framed = await openAvatarCrop(context, source: source);
    if (framed != null && mounted) setState(() => _newAvatar = XFile(framed));
  }

  void _chooseAvatarSource() {
    showModalBottomSheet<void>(
      context: context, useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppColors.ink2,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(sheet);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать снимок'),
              onTap: () {
                Navigator.pop(sheet);
                _pickAvatar(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final user = await ref.read(authRepositoryProvider).updateProfile(
        displayName: _name.text,
        city: _city.text,
        bio: _bio.text,
        avatarLocalPath: _newAvatar?.path,
      );

      // Аватар и имя зашиты в посты и комментарии, уже лежащие в списках:
      // сбрасываем их, чтобы не показывать старого себя до перезапуска.
      ref.invalidate(userProfileProvider(user.id));
      ref.invalidate(userPostsProvider(user.id));
      ref.invalidate(myPostsProvider);
      await ref.read(feedProvider.notifier).refresh();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.canPop() ? context.pop() : context.go(Routes.profile);
      messenger.showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
    } catch (error) {
      AppLog.add('Профиль не сохранился: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: 'Не удалось сохранить профиль')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final avatarUrl = _newAvatar?.path ?? me?.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать профиль'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: AppSpacing.page(context, top: 20),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: 'Сменить фото профиля',
              child: GestureDetector(
                onTap: _chooseAvatarSource,
                child: Stack(
                  children: [
                    UserAvatar(
                      name: _name.text.isEmpty ? '?' : _name.text,
                      url: avatarUrl,
                      radius: 52,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primary,
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 16,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _chooseAvatarSource,
                child: const Text('Сменить фото'),
              ),
              if (avatarUrl != null)
                TextButton(
                  onPressed: () => _adjustAvatar(avatarUrl),
                  child: const Text('Настроить кадр'),
                ),
            ],
          ),
          if (Features.videoAvatar) _VideoAvatarTile(),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Имя'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _city,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Город'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bio,
            maxLength: 300,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'О себе',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _valid && !_busy ? _save : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
