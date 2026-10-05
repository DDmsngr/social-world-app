import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';

/// Настройка кадра аватара: фото двигается и масштабируется под круглой
/// маской, так что видно ровно то, что окажется в кружке. Возвращает путь к
/// готовому квадрату (его и загружаем как аватар) или null, если человек
/// передумал.
Future<String?> openAvatarCrop(BuildContext context, {required String source}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarCropScreen(source: source),
    ),
  );
}

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.source});

  /// Ссылка или путь к файлу с фото.
  final String source;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const _outputSide = 720.0;

  final _boundary = GlobalKey();
  final _controller = TransformationController();
  late final ImageProvider _provider = imageProviderFor(widget.source);
  Size? _imageSize;
  bool _failed = false;
  bool _saving = false;
  double _side = 0;

  @override
  void initState() {
    super.initState();
    final stream = _provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      },
      onError: (error, _) {
        stream.removeListener(listener);
        AppLog.add('Фото для кадрирования не открылось: $error');
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Размер фото, при котором меньшая сторона ровно закрывает квадрат.
  Size _coverSize(Size image, double side) {
    final scale = side / (image.width < image.height ? image.width : image.height);
    return Size(image.width * scale, image.height * scale);
  }

  /// Ставит фото по центру при первом показе.
  void _center(Size cover) {
    _controller.value = Matrix4.identity()
      ..setTranslationRaw(-(cover.width - _side) / 2, -(cover.height - _side) / 2, 0);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final box = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await box.toImage(pixelRatio: _outputSide / _side);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Кадр не получился');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/avatar_${const Uuid().v4()}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (error) {
      AppLog.add('Кадр аватара не сохранился: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить кадр')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Положение фото'),
        actions: [
          TextButton(
            onPressed: image == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Готово'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _failed
                    ? const Text(
                        'Фото не открылось',
                        style: TextStyle(color: Colors.white70),
                      )
                    : image == null
                    ? const CircularProgressIndicator()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final side = (constraints.biggest.shortestSide - 32).clamp(
                            200.0,
                            520.0,
                          );
                          if (_side != side) {
                            _side = side;
                            final cover = _coverSize(image, side);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _center(cover);
                            });
                          }
                          final cover = _coverSize(image, side);
                          return SizedBox.square(
                            dimension: side,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // То, что уйдёт в аватар: только фото в квадрате,
                                // без маски и подсказок.
                                RepaintBoundary(
                                  key: _boundary,
                                  child: ClipRect(
                                    child: InteractiveViewer(
                                      transformationController: _controller,
                                      constrained: false,
                                      minScale: 1,
                                      maxScale: 6,
                                      boundaryMargin: EdgeInsets.zero,
                                      child: SizedBox(
                                        width: cover.width,
                                        height: cover.height,
                                        child: Image(
                                          image: _provider,
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.medium,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Круглая «прорезь»: за её пределами затемнение.
                                IgnorePointer(child: CustomPaint(painter: _CircleMask())),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Text(
                'Двигайте фото и меняйте масштаб двумя пальцами. '
                'В кружке будет то, что внутри круга.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleMask extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect)
      ..addOval(rect);
    canvas.drawPath(path, Paint()..color = const Color(0xB3000000));
    canvas.drawOval(
      rect.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.primaryTint,
    );
  }

  @override
  bool shouldRepaint(_CircleMask old) => false;
}
