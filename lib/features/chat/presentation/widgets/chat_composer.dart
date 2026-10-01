import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/network/vpn_check.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/secure_chat_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_meta.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/schedule_format.dart';
import '../providers/chat_providers.dart';
import 'attachment_views.dart';
import 'emoji_panel.dart';
import 'scheduled_sheet.dart';
import 'video_note_recorder.dart';

/// Поле ввода чата: текст с эмодзи, вложения (фото, камера, видео, файл),
/// голосовое и кружок. Всё, что умел DDChat, кроме звонков.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.conversationId,
    this.isDirect = true,
    this.peerName,
    this.replyTo,
    this.onReplyCleared,
  });

  final String conversationId;

  /// «Когда будет в сети» есть только в личных диалогах: в группе непонятно,
  /// кого ждать.
  final bool isDirect;
  final String? peerName;

  /// Ответ, который уйдёт вместе со следующим сообщением.
  final ChatReply? replyTo;
  final VoidCallback? onReplyCleared;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  static const _maxVoice = Duration(minutes: 5);

  /// Сколько ждать ответа сервера на текст. Без предела отправка после
  /// выключения VPN висела молча: сокет остаётся на исчезнувшей сети.
  static const sendTimeout = Duration(seconds: 20);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _emojiOpen = false;
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  bool _sendingText = false;
  String? _error;

  /// Что сейчас загружается — показывается полоской над полем.
  final _uploads = <String>[];

  bool _recording = false;
  String? _voicePath;
  final _stopwatch = Stopwatch();
  final _amplitudes = <double>[];
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    // Клавиатура и панель эмодзи занимают одно место — открыта одна из них.
    if (_focus.hasFocus && _emojiOpen) setState(() => _emojiOpen = false);
    _syncActive();
  }

  void _syncActive() => chatEmojiPanelOpen.value = _emojiOpen;

  void _toggleEmoji() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _emojiOpen = true);
    }
    _syncActive();
  }

  void _insertEmoji(String emoji) {
    _controller.value = insertAtSelection(_controller.value, emoji);
    setState(() {});
  }

  void _backspace() {
    _controller.value = deleteBeforeSelection(_controller.value);
    setState(() {});
  }

  @override
  void dispose() {
    // Сброс после кадра: dispose идёт, пока дерево заблокировано, и
    // слушатель (оболочка) не может перестроиться прямо сейчас.
    if (chatEmojiPanelOpen.value) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatEmojiPanelOpen.value = false,
      );
    }
    _focus.dispose();
    _ticker?.cancel();
    _recorder.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── текст ─────────────────────────────────────────────────────────────

  Future<void> _sendText({bool silent = false}) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sendingText) return;
    setState(() {
      _sendingText = true;
      _error = null;
    });
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(
            conversationId: widget.conversationId,
            text: text,
            options: SendOptions(replyTo: widget.replyTo, silent: silent),
          )
          .timeout(sendTimeout);
      _controller.clear();
      widget.onReplyCleared?.call();
      _afterSend();
    } on TimeoutException catch (error) {
      AppLog.add('Отправка не дождалась ответа: $error');
      final vpn = await isVpnActive();
      if (!mounted) return;
      setState(() {
        _error = vpn
            ? 'Сервер не ответил. Включён VPN — отключите его и отправьте ещё раз.'
            : 'Сервер не ответил. Проверьте интернет. Если вы только что '
                  'выключили VPN, закройте приложение и откройте снова.';
      });
    } catch (error) {
      _fail(error, 'Не удалось отправить сообщение');
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  // ── отправка «особым способом» (долгий тап по кнопке) ───────────────────

  Future<void> _showSendOptions() async {
    if (_controller.text.trim().isEmpty || _sendingText) return;
    HapticFeedback.mediumImpact();
    final mode = await showModalBottomSheet<_SendMode>(
      context: context,
      backgroundColor: AppColors.ink2,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (mode, icon, label) in [
              (
                _SendMode.silent,
                Icons.notifications_off_outlined,
                'Отправить без звука',
              ),
              (_SendMode.later, Icons.schedule, 'Отправить потом'),
              if (widget.isDirect)
                (
                  _SendMode.whenOnline,
                  Icons.person_pin_circle_outlined,
                  'Когда будет в сети',
                ),
            ])
              ListTile(
                leading: Icon(icon, color: AppColors.textDim),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    switch (mode) {
      case _SendMode.silent:
        await _sendText(silent: true);
      case _SendMode.later:
        await _scheduleLater();
      case _SendMode.whenOnline:
        await _schedule(whenOnline: true);
    }
  }

  Future<void> _scheduleLater() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(maxScheduleLead),
      helpText: 'Когда отправить',
    );
    if (date == null || !mounted) return;
    final soon = now.add(const Duration(hours: 1));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: soon.hour, minute: soon.minute),
    );
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final problem = validateSendAt(at, DateTime.now());
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    await _schedule(sendAt: at);
  }

  Future<void> _schedule({DateTime? sendAt, bool whenOnline = false}) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sendingText = true;
      _error = null;
    });
    try {
      await ref
          .read(chatRepositoryProvider)
          .scheduleText(
            conversationId: widget.conversationId,
            text: text,
            sendAt: sendAt,
            whenOnline: whenOnline,
            options: SendOptions(replyTo: widget.replyTo),
          )
          .timeout(sendTimeout);
      _controller.clear();
      widget.onReplyCleared?.call();
      ref.invalidate(scheduledMessagesProvider(widget.conversationId));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            whenOnline
                ? 'Отправим, когда ${widget.peerName ?? 'собеседник'} появится в сети'
                : 'Отправим ${formatScheduledAt(sendAt!, DateTime.now())}',
          ),
        ),
      );
    } on ChatFeatureUnavailable catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } on TimeoutException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Сервер не ответил. Попробуйте ещё раз')),
      );
    } catch (error) {
      _fail(error, 'Не удалось запланировать сообщение');
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  // ── вложения ─────────────────────────────────────────────────────────────

  Future<void> _upload({
    required MessageKind kind,
    required String path,
    String? name,
    String? mime,
    int? durationMs,
    List<double>? waveform,
  }) async {
    final label = name ?? kind.preview;
    final reply = widget.replyTo;
    setState(() {
      _uploads.add(label);
      _error = null;
    });
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendAttachment(
            conversationId: widget.conversationId,
            kind: kind,
            filePath: path,
            name: name,
            mime: mime,
            durationMs: durationMs,
            waveform: waveform,
            options: SendOptions(replyTo: reply),
          );
      if (reply != null) widget.onReplyCleared?.call();
      _afterSend();
    } catch (error) {
      _fail(error, 'Не удалось отправить: $label');
    } finally {
      if (mounted) setState(() => _uploads.remove(label));
    }
  }

  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.ink2,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, icon, label) in const [
              ('photos', Icons.photo_library_outlined, 'Фото из галереи'),
              ('camera', Icons.photo_camera_outlined, 'Сделать фото'),
              ('video', Icons.video_library_outlined, 'Видео из галереи'),
              ('file', Icons.attach_file, 'Файл'),
            ])
              ListTile(
                leading: Icon(icon, color: AppColors.textDim),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );

    try {
      switch (choice) {
        case 'photos':
          final images = await _picker.pickMultiImage(
            imageQuality: 85,
            maxWidth: 2560,
            maxHeight: 2560,
          );
          for (final image in images) {
            await _upload(
              kind: MessageKind.image,
              path: image.path,
              name: image.name,
              mime: 'image/jpeg',
            );
          }
        case 'camera':
          final image = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            maxWidth: 2560,
            maxHeight: 2560,
          );
          if (image != null) {
            await _upload(
              kind: MessageKind.image,
              path: image.path,
              name: image.name,
              mime: 'image/jpeg',
            );
          }
        case 'video':
          final video = await _picker.pickVideo(source: ImageSource.gallery);
          if (video != null) {
            await _upload(
              kind: MessageKind.video,
              path: video.path,
              name: video.name,
              mime: 'video/mp4',
            );
          }
        case 'file':
          final file = await FilePicker.pickFile();
          final path = file?.path;
          if (file != null && path != null) {
            await _upload(
              kind: MessageKind.file,
              path: path,
              name: file.name,
              mime: mimeFromName(file.name),
            );
          }
      }
    } catch (error) {
      _fail(error, 'Не удалось выбрать файл');
    }
  }

  // ── голосовое ────────────────────────────────────────────────────────────

  Future<void> _startVoice() async {
    try {
      if (!await _recorder.hasPermission()) {
        _fail(StateError('mic'), 'Нет доступа к микрофону');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: path,
      );
      _amplitudes.clear();
      _stopwatch
        ..reset()
        ..start();
      // Громкость 10 раз в секунду: из неё рисуется волна, которая уходит
      // получателю вместе с файлом (в DDChat она оставалась у отправителя).
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        try {
          final amp = await _recorder.getAmplitude();
          _amplitudes.add(((amp.current + 50) / 50).clamp(0.0, 1.0));
        } catch (_) {}
        if (_stopwatch.elapsed >= _maxVoice) {
          unawaited(_stopVoice(send: true));
        } else if (mounted) {
          setState(() {});
        }
      });
      setState(() {
        _recording = true;
        _voicePath = path;
        _error = null;
      });
    } catch (error) {
      _fail(error, 'Не удалось начать запись');
    }
  }

  Future<void> _stopVoice({required bool send}) async {
    if (!_recording) return;
    _ticker?.cancel();
    _stopwatch.stop();
    final duration = _stopwatch.elapsed;
    final waveform = downsample(List.of(_amplitudes), 48);
    setState(() => _recording = false);

    String? path;
    try {
      path = await _recorder.stop() ?? _voicePath;
    } catch (error) {
      AppLog.add('Запись не остановилась: $error');
    }
    if (path == null) return;
    if (!send || duration < const Duration(seconds: 1)) {
      await File(path).delete().catchError((_) => File(path!));
      return;
    }
    await _upload(
      kind: MessageKind.voice,
      path: path,
      name: 'voice.m4a',
      mime: 'audio/mp4',
      durationMs: duration.inMilliseconds,
      waveform: waveform,
    );
  }

  // ── кружок ───────────────────────────────────────────────────────────────

  Future<void> _recordVideoNote() async {
    final result = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<VideoNoteResult>(
        fullscreenDialog: true,
        builder: (_) => const VideoNoteRecorderScreen(),
      ),
    );
    if (result == null) return;
    await _upload(
      kind: MessageKind.videoNote,
      path: result.path,
      name: 'video_note.mp4',
      mime: 'video/mp4',
      durationMs: result.duration.inMilliseconds,
    );
  }

  // ── общее ────────────────────────────────────────────────────────────────

  void _afterSend() {
    // Новый личный диалог появляется в списке только после первого сообщения.
    ref.invalidate(conversationsProvider);
  }

  void _fail(Object error, String fallback) {
    AppLog.add('$fallback: $error');
    if (!mounted) return;
    setState(() {
      _error = error is ChatAttachmentTooLarge
          ? error.toString()
          : friendlyError(error, fallback: fallback);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_uploads.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Отправляется: ${_uploads.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 6),
            ],
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            ScheduledChip(
              conversationId: widget.conversationId,
              peerName: widget.peerName,
            ),
            if (widget.replyTo != null)
              _ReplyBar(
                reply: widget.replyTo!,
                onClose: widget.onReplyCleared ?? () {},
              ),
            if (_recording) _recordingBar() else _inputRow(hasText),
            if (_emojiOpen && !_recording)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: EmojiPanel(
                  onPick: _insertEmoji,
                  onBackspace: _backspace,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// До скольких строк растёт поле: около трети экрана над клавиатурой,
  /// дальше текст прокручивается внутри.
  int _maxLines(BuildContext context) {
    final height =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return (height * 0.35 / 24).floor().clamp(4, 12);
  }

  Widget _inputRow(bool hasText) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          onPressed: _toggleEmoji,
          tooltip: _emojiOpen ? 'Клавиатура' : 'Эмодзи',
          icon: Icon(
            _emojiOpen
                ? Icons.keyboard_alt_outlined
                : Icons.emoji_emotions_outlined,
            color: _emojiOpen ? AppColors.primaryTint : AppColors.textDim,
          ),
        ),
        IconButton(
          onPressed: _showAttachMenu,
          tooltip: 'Вложение',
          icon: Icon(Icons.attach_file, color: AppColors.textDim),
        ),
        Expanded(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.bottomCenter,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: (_) => setState(() {}),
              onTap: () {
                if (_emojiOpen) setState(() => _emojiOpen = false);
                _syncActive();
              },
              minLines: 1,
              maxLines: _maxLines(context),
              maxLength: 4000,
              keyboardType: TextInputType.multiline,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                color: AppColors.text,
              ),
              decoration: InputDecoration(
                hintText: 'Сообщение',
                isDense: true,
                constraints: const BoxConstraints(minHeight: 48),
                contentPadding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                border: _fieldBorder(AppColors.hair),
                enabledBorder: _fieldBorder(AppColors.hair),
                focusedBorder: _fieldBorder(AppColors.hairStrong),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (hasText)
          // Без tooltip: его собственный долгий тап спорил бы с меню отправки.
          Semantics(
            label: 'Отправить',
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Отправить без звука'): () =>
                  _sendText(silent: true),
              const CustomSemanticsAction(label: 'Отправить потом'): _scheduleLater,
              if (widget.isDirect)
                const CustomSemanticsAction(label: 'Когда будет в сети'): () =>
                    _schedule(whenOnline: true),
            },
            child: GestureDetector(
              onLongPress: _sendingText ? null : _showSendOptions,
              child: _RoundButton(
                icon: Icons.send,
                tooltip: null,
                accent: true,
                onPressed: _sendingText ? null : _sendText,
              ),
            ),
          )
        else ...[
          IconButton(
            onPressed: _recordVideoNote,
            tooltip: 'Видеосообщение',
            icon: Icon(Icons.radio_button_checked, color: AppColors.textDim),
          ),
          _RoundButton(
            icon: Icons.mic,
            tooltip: 'Голосовое',
            onPressed: _startVoice,
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide(color: color),
  );

  Widget _recordingBar() {
    final bars = downsample(
      _amplitudes.length > 40
          ? _amplitudes.sublist(_amplitudes.length - 40)
          : _amplitudes,
      40,
    );
    return Row(
      children: [
        IconButton(
          onPressed: () => _stopVoice(send: false),
          tooltip: 'Отменить',
          icon: Icon(Icons.delete_outline, color: AppColors.danger),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatDuration(_stopwatch.elapsed),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                for (final v in bars)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 0.8),
                      height: 3 + 25 * v,
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.send,
          tooltip: 'Отправить голосовое',
          accent: true,
          onPressed: () => _stopVoice(send: true),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent = false,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Отправка — единственная акцентная кнопка; микрофон и остальное
  /// нейтральные, чтобы нижняя панель не спорила с перепиской.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: accent ? AppColors.primaryTint : AppColors.bubbleMine,
        foregroundColor: accent ? AppColors.onPrimary : AppColors.onBubbleMine,
        disabledBackgroundColor: AppColors.card,
        disabledForegroundColor: AppColors.textFaint,
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// MIME по расширению — чтобы на стороне получателя файл открывался нужным
/// приложением.
String? mimeFromName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'ogg' => 'audio/ogg',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'zip' => 'application/zip',
    'rar' => 'application/vnd.rar',
    '7z' => 'application/x-7z-compressed',
    'apk' => 'application/vnd.android.package-archive',
    _ => null,
  };
}

enum _SendMode { silent, later, whenOnline }

/// Над полем ввода: на что отвечаем. Крестик отменяет ответ.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.reply, required this.onClose});

  final ChatReply reply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.primaryTint, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ответ: ${reply.senderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryTint,
                  ),
                ),
                Text(
                  reply.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Отменить ответ',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
