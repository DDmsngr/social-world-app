import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/events/presentation/providers/events_providers.dart';
import '../../features/feed/presentation/providers/feed_providers.dart';
import '../../features/moderation/presentation/providers/report_providers.dart';
import '../../features/notifications/notifications.dart';
import '../../features/profile/presentation/providers/profile_providers.dart';
import '../../features/saved/saved.dart';
import '../../features/routes/presentation/providers/route_recorder.dart';

/// Провайдеры, у которых состояние привязано к тому, кто именно сейчас
/// вошёл — вызывается при смене подтверждённого UID (включая выход), а не
/// при любом обновлении токена/профиля у того же человека.
///
/// [chatRepositoryProvider] — самое чувствительное место: репозиторий
/// захватывает userId один раз при создании и не отпускает его сам; без
/// сброса вход другого человека на этом же устройстве продолжил бы слать
/// сообщения от имени предыдущего.
void resetSessionScopedProviders(Ref ref) {
  ref.invalidate(feedProvider);
  ref.invalidate(eventsProvider);
  ref.invalidate(reportRepositoryProvider);
  ref.invalidate(profileRepositoryProvider);
  ref.invalidate(blocksProvider);
  ref.invalidate(savedProvider);
  ref.invalidate(notificationsProvider);
  ref.invalidate(chatRepositoryProvider);
  ref.invalidate(routeRecorderProvider);
}
