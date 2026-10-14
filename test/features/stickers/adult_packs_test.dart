import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/stickers/sticker_providers.dart';

import 'sticker_fixtures.dart';

// Возраст и стикеры 18+: паки с матом видят только совершеннолетние.

const _adultPacks = ['palych', 'viking', 'stanochnik', 'arturio'];

DateTime _yearsAgo(int years, {int days = 0}) {
  final now = DateTime.now();
  return DateTime(now.year - years, now.month, now.day).subtract(Duration(days: days));
}

ProviderContainer _container(AppUser user) {
  final backend = FakeStickerBackend(installed: [..._adultPacks, 'alexa']);
  return ProviderContainer(
    overrides: [
      stickerBackendProvider.overrideWithValue(backend),
      currentUserProvider.overrideWithValue(user),
    ],
  );
}

Future<List<String>> _visiblePackIds(ProviderContainer container) async {
  await container.read(stickerCatalogProvider.future);
  return [for (final p in container.read(visibleStickerCatalogProvider).requireValue.packs) p.id];
}

void main() {
  useTestStickerImages();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('возраст в профиле', () {
    test('считается в полных годах: день рождения ещё впереди — на год меньше', () {
      final now = DateTime(2026, 10, 14);
      expect(AppUser(id: 'a', birthDate: DateTime(2008, 10, 14)).ageOn(now), 18);
      expect(AppUser(id: 'a', birthDate: DateTime(2008, 10, 15)).ageOn(now), 17);
      expect(AppUser(id: 'a', birthDate: DateTime(2000, 1, 1)).ageOn(now), 26);
      expect(const AppUser(id: 'a').ageOn(now), isNull);
    });

    test('сервер просит возраст у всех: без даты — на экран возраста', () {
      expect(const AppUser(id: 'a', ageRequired: true).needsAge, isTrue);
      expect(AppUser(id: 'a', ageRequired: true, birthDate: _yearsAgo(30)).needsAge, isFalse);
      // Локальный режим и тесты возраст не требуют.
      expect(const AppUser(id: 'a').needsAge, isFalse);
    });

    test('совершеннолетний: ровно 18 — да, без дня 18 — нет, без даты при обязательном возрасте — нет', () {
      expect(AppUser(id: 'a', ageRequired: true, birthDate: _yearsAgo(18)).isAdult, isTrue);
      expect(AppUser(id: 'a', ageRequired: true, birthDate: _yearsAgo(18, days: -1)).isAdult, isFalse);
      expect(AppUser(id: 'a', ageRequired: true, birthDate: _yearsAgo(15)).isAdult, isFalse);
      expect(const AppUser(id: 'a', ageRequired: true).isAdult, isFalse);
      expect(const AppUser(id: 'a').isAdult, isTrue);
    });
  });

  group('каталог стикеров', () {
    test('четыре пака с матом помечены 18+, остальные нет', () {
      final catalog = catalogFromSources();
      for (final pack in catalog.packs) {
        expect(pack.adult, _adultPacks.contains(pack.id), reason: pack.id);
      }
    });

    test('withoutAdult: паков 18+ нет, стикеры из них не находятся', () {
      final catalog = catalogFromSources();
      final clean = catalog.withoutAdult();
      expect([for (final p in clean.packs) p.id], isNot(contains('palych')));
      expect(catalog.byId('palych.${catalog.pack('palych')!.stickers.first.key}'), isNotNull);
      expect(clean.byId('palych.${catalog.pack('palych')!.stickers.first.key}'), isNull);
      expect(clean.packs, hasLength(catalog.packs.length - _adultPacks.length));
    });
  });

  group('что видит человек', () {
    test('взрослому — все паки', () async {
      final container = _container(AppUser(id: 'me', ageRequired: true, birthDate: _yearsAgo(30)));
      addTearDown(container.dispose);
      expect(await _visiblePackIds(container), containsAll(_adultPacks));
    });

    test('младше 18 — паков 18+ нет ни в магазине, ни среди своих', () async {
      final container = _container(AppUser(id: 'me', ageRequired: true, birthDate: _yearsAgo(16)));
      addTearDown(container.dispose);
      final visible = await _visiblePackIds(container);
      for (final id in _adultPacks) {
        expect(visible, isNot(contains(id)));
      }
      await container.read(installedStickerPacksProvider.future);
      final mine = [for (final p in container.read(myStickerPacksProvider)) p.id];
      expect(mine, ['alexa']);
    });

    test('возраст не назван (уже вошёл, но экран возраста не прошёл) — как младше 18', () async {
      final container = _container(const AppUser(id: 'me', ageRequired: true));
      addTearDown(container.dispose);
      final visible = await _visiblePackIds(container);
      for (final id in _adultPacks) {
        expect(visible, isNot(contains(id)));
      }
    });
  });
}
