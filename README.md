# Social World — приложение

Flutter-приложение для пилота в Сочи. Питч-сайт проекта — [ddmsngr.github.io/social-world](https://ddmsngr.github.io/social-world/).

Фаза 0 по плану: каркас навигации, авторизация, дизайн-система, схема базы и размытие геопозиции.

## Запуск

```bash
cp .env.example .env     # ключи бэкенда, пока можно оставить пустыми
flutter pub get
flutter run
```

Без заполненного `.env` приложение поднимается на локальных заглушках: вход работает, код подтверждения — любые шесть цифр. Это сделано, чтобы собирать интерфейс, не дожидаясь сервера.

```bash
flutter analyze
flutter test
```

## Структура

```
lib/
  core/
    config/     — чтение .env, режим «без бэкенда»
    location/   — размытие геопозиции
    router/     — go_router, редиректы по состоянию сессии
    theme/      — палитра и типографика с питч-сайта
    widgets/    — общие элементы
  features/
    auth/       — domain / data / presentation
    shell/      — нижняя навигация, четыре вкладки
    feed/ discover/ create/ profile/
supabase/
  migrations/   — SQL-схема
```

Слои те же, что в SLED и KOTT: `domain` не знает ни про Supabase, ни про Flutter, `data` реализует интерфейсы репозиториев, `presentation` держит Riverpod-провайдеры и экраны.

## Геопозиция

Точные координаты не уходят с устройства. `GeoPrivacy.blur` привязывает точку к центру ячейки сетки выбранного размера (по умолчанию 500 м), сетка сдвинута на соль пользователя — чтобы по чужим точкам нельзя было восстановить решётку. В базу пишется только результат размытия и радиус.

Проверено тестами: `test/core/location/geo_privacy_test.dart`.

## Стек

| | |
|---|---|
| Flutter | 3.44, Dart 3.12 |
| Состояние | Riverpod 3 |
| Навигация | go_router 18 |
| Бэкенд | Supabase (self-hosted, см. `supabase/README.md`) |
| Карта | Яндекс MapKit — с фазы 2 |
| Push | FCM — с фазы 3 |

Bundle id: `ru.socialworld.app`.
