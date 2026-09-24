import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/update/update_controller.dart';
import 'package:social_world/core/update/update_dot.dart';
import 'package:social_world/core/update/update_info.dart';

// «Хлебные крошки» обновления: зелёная точка на «Профиле», у шестерёнки и
// зелёная строка в настройках горят от одного признака UpdateState.hasUpdate.
// Ошибка проверки без найденной версии (нет сети) обновлением не считается.
const _info = UpdateInfo(
  versionCode: 5071,
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
  group('UpdateState.hasUpdate', () {
    test('горит, пока есть что поставить', () {
      for (final stage in [
        UpdateStage.available,
        UpdateStage.downloading,
        UpdateStage.readyToInstall,
      ]) {
        expect(
          UpdateState(stage: stage, info: _info).hasUpdate,
          isTrue,
          reason: '$stage',
        );
      }
    });

    test('не гаснет, если скачивание сорвалось, а версия найдена', () {
      expect(
        const UpdateState(stage: UpdateStage.failed, info: _info).hasUpdate,
        isTrue,
      );
    });

    test('сбой самой проверки (нет сети) — не обновление', () {
      expect(const UpdateState(stage: UpdateStage.failed).hasUpdate, isFalse);
    });

    test('проверяется, актуально, ничего не было — не горит', () {
      for (final stage in [
        UpdateStage.idle,
        UpdateStage.checking,
        UpdateStage.upToDate,
      ]) {
        expect(UpdateState(stage: stage).hasUpdate, isFalse, reason: '$stage');
      }
    });
  });

  Future<void> pump(WidgetTester tester, UpdateState state) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateControllerProvider.overrideWith(() => _Fake(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UpdateDot(child: Icon(Icons.person_outline))),
          ),
        ),
      );

  testWidgets('точка видна, когда обновление есть', (tester) async {
    await pump(
      tester,
      const UpdateState(stage: UpdateStage.available, info: _info),
    );
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
  });

  testWidgets('точки нет, когда обновлений нет', (tester) async {
    await pump(tester, const UpdateState(stage: UpdateStage.upToDate));
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    expect(
      find.byIcon(Icons.person_outline),
      findsOneWidget,
      reason: 'иконка на месте в любом случае',
    );
  });
}
