import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../../../core/theme/app_colors.dart';

/// Выбранные фото перед отправкой: листать, «Изменить» (рисовать, обрезать,
/// повернуть, текст, фильтры), убрать лишнее. Возвращает пути к тому, что
/// отправить, или null, если передумали.
Future<List<String>?> showPhotoSendScreen(BuildContext context, List<String> paths) {
  return Navigator.of(context, rootNavigator: true).push<List<String>>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PhotoSendScreen(paths)),
  );
}

class _PhotoSendScreen extends StatefulWidget {
  const _PhotoSendScreen(this.initial);

  final List<String> initial;

  @override
  State<_PhotoSendScreen> createState() => _PhotoSendScreenState();
}

class _PhotoSendScreenState extends State<_PhotoSendScreen> {
  late final List<String> _paths = [...widget.initial];
  final _pages = PageController();
  var _index = 0;

  Future<void> _edit() async {
    final edited = await editPhoto(context, _paths[_index]);
    if (edited != null && mounted) setState(() => _paths[_index] = edited);
  }

  void _remove() {
    setState(() {
      _paths.removeAt(_index);
      if (_index >= _paths.length) _index = _paths.length - 1;
    });
    if (_paths.isEmpty) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = _paths.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(many ? 'Фото ${_index + 1} из ${_paths.length}' : 'Фото'),
        actions: [
          if (many)
            IconButton(tooltip: 'Убрать это фото', onPressed: _remove, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _paths.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(
                  // Ключ по пути: после правки картинка должна перерисоваться.
                  child: Image.file(File(_paths[i]), key: ValueKey(_paths[i]), fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _edit,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Изменить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(_paths),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      icon: const Icon(Icons.send),
                      label: Text(many ? 'Отправить ${_paths.length}' : 'Отправить'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Редактор одного фото. Возвращает путь к изменённой копии или null, если
/// закрыли без сохранения.
Future<String?> editPhoto(BuildContext context, String path) async {
  Uint8List? result;
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (editorContext) => ProImageEditor.file(
        File(path),
        configs: const ProImageEditorConfigs(
          i18n: _ruI18n,
          mainEditor: MainEditorConfigs(
            tools: [
              SubEditorMode.paint,
              SubEditorMode.cropRotate,
              SubEditorMode.text,
              SubEditorMode.tune,
              SubEditorMode.filter,
              SubEditorMode.emoji,
            ],
          ),
        ),
        callbacks: ProImageEditorCallbacks(
          onImageEditingComplete: (bytes) async {
            result = bytes;
            Navigator.of(editorContext).pop();
          },
        ),
      ),
    ),
  );
  final bytes = result;
  if (bytes == null) return null;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await file.writeAsBytes(bytes);
  return file.path;
}

const _ruI18n = I18n(
  cancel: 'Отмена',
  undo: 'Отменить',
  redo: 'Вернуть',
  done: 'Готово',
  remove: 'Удалить',
  doneLoadingMsg: 'Сохраняем…',
  importStateHistoryMsg: '',
  various: I18nVarious(
    loadingDialogMsg: 'Подождите…',
    closeEditorWarningTitle: 'Выйти из редактора?',
    closeEditorWarningMessage: 'Изменения не сохранятся.',
    closeEditorWarningConfirmBtn: 'Выйти',
    closeEditorWarningCancelBtn: 'Остаться',
  ),
  layerInteraction: I18nLayerInteraction(remove: 'Удалить', edit: 'Изменить', rotateScale: 'Повернуть и масштабировать'),
  paintEditor: I18nPaintEditor(
    moveAndZoom: 'Масштаб',
    bottomNavigationBarText: 'Рисовать',
    freestyle: 'Кисть',
    freestyleArrowStart: 'Кисть со стрелкой в начале',
    freestyleArrowEnd: 'Кисть со стрелкой в конце',
    freestyleArrowStartEnd: 'Кисть со стрелками',
    arrow: 'Стрелка',
    line: 'Линия',
    rectangle: 'Прямоугольник',
    circle: 'Круг',
    dashLine: 'Пунктир',
    dashDotLine: 'Штрих-пунктир',
    hexagon: 'Шестиугольник',
    polygon: 'Многоугольник',
    blur: 'Размытие',
    pixelate: 'Пиксели',
    lineWidth: 'Толщина',
    eraser: 'Ластик',
    toggleFill: 'Заливка',
    changeOpacity: 'Прозрачность',
    undo: 'Отменить',
    redo: 'Вернуть',
    done: 'Готово',
    back: 'Назад',
    smallScreenMoreTooltip: 'Ещё',
    opacity: 'Прозрачность',
    color: 'Цвет',
    strokeWidth: 'Толщина',
    fill: 'Заливка',
    cancel: 'Отмена',
  ),
  cropRotateEditor: I18nCropRotateEditor(
    bottomNavigationBarText: 'Обрезать',
    rotate: 'Повернуть',
    flip: 'Отразить',
    tilt: 'Наклон',
    tiltRotate: 'Поворот',
    tiltHorizontal: 'По горизонтали',
    tiltVertical: 'По вертикали',
    ratio: 'Пропорции',
    back: 'Назад',
    done: 'Готово',
    cancel: 'Отмена',
    undo: 'Отменить',
    redo: 'Вернуть',
    smallScreenMoreTooltip: 'Ещё',
    reset: 'Сбросить',
  ),
  textEditor: I18nTextEditor(
    inputHintText: 'Введите текст',
    bottomNavigationBarText: 'Текст',
    back: 'Назад',
    done: 'Готово',
    textAlign: 'Выравнивание',
    fontScale: 'Размер',
    backgroundMode: 'Фон',
    smallScreenMoreTooltip: 'Ещё',
  ),
  tuneEditor: I18nTuneEditor(
    bottomNavigationBarText: 'Настроить',
    back: 'Назад',
    done: 'Готово',
    brightness: 'Яркость',
    contrast: 'Контраст',
    saturation: 'Насыщенность',
    exposure: 'Экспозиция',
    hue: 'Оттенок',
    temperature: 'Температура',
    fade: 'Выцветание',
    tint: 'Тон',
    undo: 'Отменить',
    redo: 'Вернуть',
  ),
  filterEditor: I18nFilterEditor(bottomNavigationBarText: 'Фильтры', back: 'Назад', done: 'Готово'),
  emojiEditor: I18nEmojiEditor(
    bottomNavigationBarText: 'Эмодзи',
    search: 'Поиск',
    categoryRecent: 'Недавние',
    categorySmileys: 'Смайлы и люди',
    categoryAnimals: 'Животные и природа',
    categoryFood: 'Еда и напитки',
    categoryActivities: 'Занятия',
    categoryTravel: 'Путешествия',
    categoryObjects: 'Предметы',
    categorySymbols: 'Символы',
    categoryFlags: 'Флаги',
  ),
);
