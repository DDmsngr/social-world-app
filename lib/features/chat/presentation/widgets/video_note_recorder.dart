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

/// Запись кружка: фронтальная камера, круглое превью, до минуты. Запись
/// начинается сразу при открытии, как в DDChat; «стоп» отправляет.
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

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Камеры нет');
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(front, ResolutionPreset.medium);
      await camera.initialize();
      // Лёгкий зум убирает «рыбий глаз» фронталки (приём из DDChat).
      try {
        final maxZoom = await camera.getMaxZoomLevel();
        await camera.setZoomLevel(1.25.clamp(1.0, maxZoom));
      } catch (_) {}
      await camera.startVideoRecording();
      _stopwatch.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_stopwatch.elapsed >= _max) {
          _finish(send: true);
        } else if (mounted) {
          setState(() {});
        }
      });
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

  Future<void> _finish({required bool send}) async {
    final camera = _camera;
    if (_finishing || camera == null) return;
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
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => camera == null
                      ? Navigator.of(context).pop()
                      : _finish(send: false),
                  tooltip: 'Отменить',
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
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
                '${formatDuration(_stopwatch.elapsed)} / ${formatDuration(_max)}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              IconButton.filled(
                onPressed: camera == null ? null : () => _finish(send: true),
                tooltip: 'Отправить',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  minimumSize: const Size(72, 72),
                ),
                icon: const Icon(Icons.send, size: 30),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
