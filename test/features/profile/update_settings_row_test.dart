import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/update/update_controller.dart';
import 'package:social_world/core/update/update_info.dart';
import 'package:social_world/features/profile/presentation/settings_screen.dart';

// Строка обновлений в настройках. На реальном телефоне слово «Обновления»
// переносилось по слогам («Обновлен / ия»): длинная подсказка справа отбирала
// у заголовка почти всю ширину. Заголовок и подсказка теперь друг под другом.
// Два основных состояния — «Версия актуальна» и «Есть обновления. Нажмите,
// чтобы скачать»; остальные нужны, чтобы кнопка довела до установки.
const _info = UpdateInfo(
  versionCode: 5073,
  versionName: '1.0.0',
  apkUrl: 'https://x/a.apk',
  notes: '',
);

class _Fake extends UpdateController {
  _Fake(this._state);
  final UpdateState _state;
  @override
  UpdateState build() => _state;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    UpdateState state, {
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateControllerProvider.overrideWith(() => _Fake(state))],
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: UpdateSettingsRow(),
            ),
          ),
        ),
      ),
    );
  }

  // Проверяем структуру, а не число строк: в тестовой среде шрифт «Ahem»,
  // где каждая буква — квадрат в кегль шириной, почти вдвое шире настоящих, и
  // перенос по нему ничего не доказывает. Баг был структурный — подсказка
  // стояла В ОДНУ СТРОКУ с заголовком и отбирала у него ширину. Значит:
  // подсказка обязана стоять ПОД заголовком, с тем же левым краем.
  void expectHintBelowTitle(WidgetTester tester, String title, String hint) {
    final t = find.text(title);
    final h = find.text(hint);
    expect(t, findsOneWidget);
    expect(h, findsOneWidget);
    expect(
      tester.getTopLeft(h).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(t).dy - 1),
      reason: 'подсказка «$hint» стоит рядом с «$title», а не под ним',
    );
    expect(tester.getTopLeft(h).dx, tester.getTopLeft(t).dx);
  }

  // заголовок → подсказка для каждого состояния
  final stages = <(String, String, UpdateState)>[
    (
      'Версия актуальна',
      'Нажмите, чтобы проверить обновления',
      const UpdateState(stage: UpdateStage.upToDate),
    ),
    (
      'Есть обновления',
      'Нажмите, чтобы скачать',
      const UpdateState(stage: UpdateStage.available, info: _info),
    ),
    (
      'Обновление готово',
      'Нажмите, чтобы установить',
      const UpdateState(stage: UpdateStage.readyToInstall, info: _info),
    ),
    (
      'Не удалось скачать',
      'Нажмите, чтобы докачать',
      const UpdateState(stage: UpdateStage.failed, info: _info),
    ),
  ];

  for (final width in [320.0, 360.0]) {
    for (final (title, hint, state) in stages) {
      testWidgets('«$title»: подсказка под заголовком на $width dp', (
        tester,
      ) async {
        await pump(tester, state, width: width);
        expectHintBelowTitle(tester, title, hint);
      });
    }
  }
  testWidgets('есть обновления — говорит, что делать', (tester) async {
    await pump(
      tester,
      const UpdateState(stage: UpdateStage.available, info: _info),
    );
    expect(find.text('Есть обновления'), findsOneWidget);
    expect(find.text('Нажмите, чтобы скачать'), findsOneWidget);
  });

  testWidgets('версия актуальна — обновлений нет, точки нет', (tester) async {
    await pump(tester, const UpdateState(stage: UpdateStage.upToDate));
    expect(find.text('Версия актуальна'), findsOneWidget);
    expect(find.byIcon(Icons.system_update_alt), findsNothing);
  });

  testWidgets('идёт скачивание — виден прогресс', (tester) async {
    await pump(
      tester,
      const UpdateState(
        stage: UpdateStage.downloading,
        info: _info,
        progress: 0.4,
      ),
    );
    expect(find.text('40%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
