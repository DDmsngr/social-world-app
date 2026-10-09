import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // Зум: щипком по кружку или кнопками громкости.
  var _zoom = 1.0;
  var _minZoom = 1.0;
  var _maxZoom = 1.0;
  var _scaleBase = 1.0;
  Timer? _zoomLabelTimer;
  var _zoomLabel = false;

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
      _minZoom = await camera.getMinZoomLevel();
      _maxZoom = await camera.getMaxZoomLevel();
      final wanted = _lens == CameraLensDirection.front ? 1.25 : 1.0;
      _zoom = wanted.clamp(_minZoom, _maxZoom);
      await camera.setZoomLevel(_zoom);
    } catch (_) {}
  }

  /// Новый зум: ограничен возможностями камеры, на экране на секунду
  /// показывается «1.8×».
  Future<void> _setZoom(double value) async {
    final camera = _camera;
    if (camera == null || _maxZoom <= _minZoom) return;
    final next = value.clamp(_minZoom, _maxZoom);
    if ((next - _zoom).abs() < 0.01) return;
    _zoom = next;
    _zoomLabelTimer?.cancel();
    setState(() => _zoomLabel = true);
    _zoomLabelTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _zoomLabel = false);
    });
    try {
      await camera.setZoomLevel(next);
    } catch (error) {
      AppLog.add('Зум кружка: $error');
    }
  }

  /// Шаг зума на одно нажатие громкости: примерно двенадцатая часть диапазона.
  double get _zoomStep => ((_maxZoom - _minZoom) / 12).clamp(0.15, 0.6);

  /// Кнопки громкости: «плюс» приближает, «минус» отдаляет. Событие
  /// съедается, поэтому системная громкость не меняется и не звучит.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      _setZoom(_zoom + _zoomStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      _setZoom(_zoom - _zoomStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    _zoomLabelTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    // Круг крупнее и выше: смотреть в камеру удобнее, когда лицо в кружке
    // рядом с объективом, а не посреди экрана.
    final screen = MediaQuery.sizeOf(context);
    final size = (screen.width * 0.94).clamp(0.0, screen.height * 0.6);
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
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
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
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      : GestureDetector(
                          // Щипок по кружку — зум.
                          onScaleStart: (_) => _scaleBase = _zoom,
                          onScaleUpdate: (details) {
                            if (details.pointerCount >= 2) _setZoom(_scaleBase * details.scale);
                          },
                          child: SizedBox.square(
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
                              Positioned(
                                bottom: size * 0.12,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: _zoomLabel ? 1 : 0,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      child: Text(
                                        '${_zoom.toStringAsFixed(1)}×',
                                        style: const TextStyle(color: Colors.white, fontSize: 15),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
      ),
    );
  }
}
