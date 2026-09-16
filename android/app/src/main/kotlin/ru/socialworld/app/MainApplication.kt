package ru.socialworld.app

import android.app.Application

/**
 * Раньше здесь инициализировался Yandex MapKit через MapKitFactory.setApiKey().
 * После перехода на официальный плагин yandex_maps_mapkit ключ задаётся в Dart
 * (см. lib/main.dart → MapkitBoot.init). Класс остаётся, потому что на него
 * ссылается AndroidManifest.xml (android:name=".MainApplication").
 */
class MainApplication : Application()
