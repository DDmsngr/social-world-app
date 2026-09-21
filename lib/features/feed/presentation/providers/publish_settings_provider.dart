import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/publish_settings.dart';

class PublishState {
  const PublishState({
    this.current = PublishSettings.defaults,
    this.presets = const [],
  });

  /// Что выбрано в форме прямо сейчас.
  final PublishSettings current;
  final List<PublishPreset> presets;

  /// Пресет, который в точности совпадает с текущим выбором. Как только
  /// человек тронул чекбокс, совпадение пропадает и чип сам снимается.
  PublishPreset? get activePreset {
    for (final preset in presets) {
      if (preset.settings == current) return preset;
    }
    return null;
  }

  PublishState copyWith({
    PublishSettings? current,
    List<PublishPreset>? presets,
  }) => PublishState(
    current: current ?? this.current,
    presets: presets ?? this.presets,
  );
}

/// Настройки публикации живут на устройстве и привязаны к человеку: у другого
/// аккаунта на том же телефоне свои «последние» и свои пресеты.
class PublishSettingsController extends Notifier<PublishState> {
  String? _uid;

  String get _lastKey => 'publish.last.$_uid';
  String get _presetsKey => 'publish.presets.$_uid';

  @override
  PublishState build() {
    ref.keepAlive();
    _uid = ref.watch(currentUserProvider.select((user) => user?.id));
    if (_uid != null) unawaited(_load());
    return const PublishState();
  }

  Future<void> _load() async {
    final uid = _uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Пока читали диск, могли сменить аккаунт или человек уже тронул форму.
      if (!ref.mounted || uid != _uid) return;

      PublishSettings? last;
      final rawLast = prefs.getString(_lastKey);
      if (rawLast != null) {
        last = PublishSettings.fromJson(
          (jsonDecode(rawLast) as Map).cast<String, dynamic>(),
        );
      }

      final presets = <PublishPreset>[];
      final rawPresets = prefs.getString(_presetsKey);
      if (rawPresets != null) {
        for (final item in jsonDecode(rawPresets) as List) {
          presets.add(
            PublishPreset.fromJson((item as Map).cast<String, dynamic>()),
          );
        }
      }
      state = PublishState(current: last ?? state.current, presets: presets);
    } catch (error) {
      // Битое значение в prefs — не повод ломать форму: остаются настройки
      // по умолчанию, а следующая публикация перезапишет мусор.
      AppLog.add('Настройки публикации не прочитались: $error');
    }
  }

  void update(PublishSettings settings) =>
      state = state.copyWith(current: settings);

  void applyPreset(PublishPreset preset) =>
      state = state.copyWith(current: preset.settings);

  /// После успешной публикации выбранное становится настройкой по умолчанию
  /// для следующего поста.
  Future<void> rememberAsDefault() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastKey, jsonEncode(state.current.toJson()));
  }

  Future<void> savePreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final preset = PublishPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed,
      settings: state.current,
    );
    state = state.copyWith(presets: [...state.presets, preset]);
    await _persistPresets();
  }

  Future<void> deletePreset(String id) async {
    state = state.copyWith(
      presets: [
        for (final preset in state.presets)
          if (preset.id != id) preset,
      ],
    );
    await _persistPresets();
  }

  Future<void> _persistPresets() async {
    if (_uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _presetsKey,
      jsonEncode([for (final preset in state.presets) preset.toJson()]),
    );
  }
}

final publishSettingsProvider =
    NotifierProvider<PublishSettingsController, PublishState>(
      PublishSettingsController.new,
    );
