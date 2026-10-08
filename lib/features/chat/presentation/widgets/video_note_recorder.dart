import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import 'attachment_views.dart';

class VideoNoteResult {
  const VideoNoteResult(this.path, this.duration);

  final String path;
  final Duration duration;
}

/// Запись кружка: круглое превью, до минуты. Сначала человек выбирает камеру
/// (по умолчанию фронтальная), потом нажимает запись; вторая кнопка отправляет.
class VideoNoteRecorderScreen extends StatefulWidget {
  const VideoNoteRecorderScreen({super.key, this.maxDuration = const Duration(seconds: 60)});

  /// Потолок записи: в чате минута, у видеоаватара — несколько секунд.
  final Duration maxDuration;

  @override
  State<VideoNoteRecorderScreen> createState() =>
      _VideoNoteRecorderScreenState();
}

class _VideoNoteRecorderScreenState extends State<VideoNoteRecorderScreen> {
  Duration get _max => widget.maxDuration;

  CameraController? _camera;
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  String? _error;
  bool _finishing = false;
  bool _switching = false;
  bool _recording = false;
  bool _canFlip = false;
  var _cameras = <CameraDescription>[];
  var _lens = CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Камеры нет');
      _cameras = cameras;
      _canFlip =
          cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
          cameras.any((c) => c.lensDirection == CameraLensDirection.back);
      final description = cameras.firstWhere(
        (c) => c.lensDirection == _lens,
        orElse: () => cameras.first,
      );
      final camera = CameraController(description, ResolutionPreset.medium);
      await camera.initialize();
      _lens = description.lensDirection;
      await _applyZoom(camera);
      if (mounted) {
        setState(() => _camera = camera);
      } else {
        await camera.dispose();
      }
    } catch (error) {
      AppLog.add('Камера для кружка: $error');
      if (mounted) {
        setState(() => _error = 'Нет доступа к камере или микрофону');
      }
    }
  }

  /// Запись идёт только после нажатия: до этого человек выбирает камеру.
  Future<void> _beginRecording() async {
    final camera = _camera;
    if (camera == null || _recording || _switching) return;
    try {
      await camera.startVideoRecording();
    } catch (error) {
      AppLog.add('Кружок не начал запись: $error');
      if (mounted) setState(() => _error = 'Не удалось начать запись');
      return;
    }
    _recording = true;
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_stopwatch.elapsed >= _max) {
        _finish(send: true);
      } else if (mounted) {
        setState(() {});
      }
    });
    if (mounted) setState(() {});
  }

  CameraLensDirection get _otherLens => _lens == CameraLensDirection.front
      ? CameraLensDirection.back
      : CameraLensDirection.front;

  /// Смена камеры. Во время записи объектив переключается на лету, запись и
  /// таймер продолжаются (CameraX держит запись при смене камеры). До записи
  /// просто пересоздаётся превью.
  Future<void> _flip() async {
    final camera = _camera;
    if (_finishing || _switching || camera == null) return;
    _switching = true;
    try {
      if (_recording) {
        final target = _cameras.firstWhere(
          (c) => c.lensDirection == _otherLens,
          orElse: () => camera.description,
        );
        await camera.setDescription(target);
        _lens = target.lensDirection;
        await _applyZoom(camera);
        if (mounted) setState(() {});
        return;
      }
      await camera.dispose();
      if (!mounted) return;
      setState(() => _camera = null);
      _lens = _otherLens;
      await _start();
    } catch (error) {
      AppLog.add('Смена камеры кружка: $error');
      if (mounted) setState(() => _error = 'Не удалось сменить камеру');
    } finally {
      _switching = false;
    }
  }

  // Лёгкий зум убирает «рыбий глаз» фронталки (приём из DDChat); у основной
  // камеры зум не нужен.
  Future<void> _applyZoom(CameraController camera) async {
    try {
      final maxZoom = await camera.getMaxZoomLevel();
      final wanted = _lens == CameraLensDirection.front ? 1.25 : 1.0;
      await camera.setZoomLevel(wanted.clamp(1.0, maxZoom));
    } catch (_) {}
  }

  Future<void> _finish({required bool send}) async {
    final camera = _camera;
    if (_finishing || _switching || camera == null) return;
    if (!_recording) {
      // Запись не начиналась — отправлять нечего.
      _finishing = true;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _finishing = true;
    _ticker?.cancel();
    _stopwatch.stop();
    try {
      final file = await camera.stopVideoRecording();
      if (!send || _stopwatch.elapsed < const Duration(seconds: 1)) {
        await File(file.path).delete().catchError((_) => File(file.path));
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (mounted) {
        Navigator.of(context).pop(VideoNoteResult(file.path, _stopwatch.elapsed));
      }
    } catch (error) {
      AppLog.add('Кружок не записался: $error');
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final size = MediaQuery.sizeOf(context).width * 0.8;
    final progress =
        _stopwatch.elapsed.inMilliseconds / _max.inMilliseconds;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (camera == null) {
          Navigator.of(context).pop();
        } else {
          _finish(send: false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => camera == null
                        ? Navigator.of(context).pop()
                        : _finish(send: false),
                    tooltip: 'Отменить',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  if (_canFlip)
                    IconButton(
                      onPressed: camera == null || _switching ? null : _flip,
                      tooltip: 'Сменить камеру',
                      icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                    ),
                ],
              ),
              Expanded(
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      : SizedBox.square(
                          dimension: size,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipOval(
                                child: SizedBox.square(
                                  dimension: size - 12,
                                  child: camera == null
                                      ? const ColoredBox(color: Colors.black)
                                      : FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            // Превью камеры отдаётся в
                                            // альбомной ориентации.
                                            width: camera.value.previewSize?.height ?? 1,
                                            height: camera.value.previewSize?.width ?? 1,
                                            child: CameraPreview(camera),
                                          ),
                                        ),
                                ),
                              ),
                              SizedBox.square(
                                dimension: size,
                                child: CircularProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  strokeWidth: 4,
                                  color: AppColors.primary,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              Text(
                _recording
                    ? '${formatDuration(_stopwatch.elapsed)} / ${formatDuration(_max)}'
                    : 'Выберите камеру и нажмите запись',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              IconButton.filled(
                onPressed: camera == null || _switching
                    ? null
                    : (_recording ? () => _finish(send: true) : _beginRecording),
                tooltip: _recording ? 'Отправить' : 'Начать запись',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  minimumSize: const Size(72, 72),
                ),
                icon: Icon(_recording ? Icons.send : Icons.fiber_manual_record, size: 30),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
