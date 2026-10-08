import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/presentation/avatar_crop_screen.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../data/channels_repository.dart';
import 'providers/channel_providers.dart';

/// Новый канал: название, описание, тип (публичный с @адресом или закрытый),
/// тема для каталога.
class CreateChannelScreen extends ConsumerStatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  ConsumerState<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends ConsumerState<CreateChannelScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _handle = TextEditingController();
  var _public = true;
  var _topic = ChannelTopic.other;
  var _busy = false;
  String? _avatarPath;

  static final _handleRe = RegExp(r'^[a-z0-9_]{4,32}$');

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _handle.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      (!_public || _handleRe.hasMatch(_handle.text.trim().toLowerCase()));

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    final path = await openAvatarCrop(context, source: picked.path);
    if (path != null && mounted) setState(() => _avatarPath = path);
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final id = await ref.read(channelsRepositoryProvider).create(
        title: _title.text.trim(),
        description: _description.text.trim(),
        isPublic: _public,
        topic: _topic,
        handle: _public ? _handle.text.trim().toLowerCase() : null,
      );
      final avatar = _avatarPath;
      if (avatar != null) {
        // Канал уже создан: если фото не загрузилось, это не повод терять его.
        try {
          await ref.read(channelsRepositoryProvider).setAvatar(id, avatar);
        } catch (error) {
          AppLog.add('Аватар нового канала: $error');
        }
      }
      ref.invalidate(conversationsProvider);
      if (!mounted) return;
      context.pushReplacement(Routes.channel(id));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось создать канал'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый канал'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.chats),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: AppSpacing.page(context, top: 16),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: 'Фото канала',
              child: GestureDetector(
                onTap: _busy ? null : _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.ink,
                      foregroundImage: _avatarPath == null ? null : FileImage(File(_avatarPath!)),
                      child: Icon(Icons.campaign_outlined, size: 38, color: AppColors.primaryTint),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primary,
                        child: const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Описание',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Публичный'), icon: Icon(Icons.public)),
              ButtonSegment(value: false, label: Text('Закрытый'), icon: Icon(Icons.lock_outline)),
            ],
            selected: {_public},
            onSelectionChanged: (value) => setState(() => _public = value.first),
          ),
          const SizedBox(height: 8),
          Text(
            _public
                ? 'Канал найдут в каталоге, читать можно без подписки.'
                : 'Вступить можно по ссылке-приглашению или по заявке, которую одобрит админ.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
          if (_public) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _handle,
              maxLength: 32,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Адрес',
                prefixText: '@',
                helperText: 'Латиница, цифры и _, от 4 символов',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 14),
          Text('Тема', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final topic in ChannelTopic.values)
                ChoiceChip(
                  label: Text(topic.label),
                  selected: _topic == topic,
                  onSelected: (_) => setState(() => _topic = topic),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _valid && !_busy ? _create : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать канал'),
          ),
        ],
      ),
    );
  }
}
