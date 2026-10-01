import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local_chat_repository.dart';
import '../../data/secure_chat_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_meta.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  // Репозиторий держит ключи и realtime-сессию, пересоздавать его нельзя.
  ref.keepAlive();
  if (Env.isConfigured) {
    final client = Supabase.instance.client;
    final userId =
        ref.read(currentUserProvider)?.id ?? client.auth.currentUser?.id;
    if (userId == null) throw StateError('Нет активной сессии для чатов');
    return SecureChatRepository(client, currentUserId: userId);
  }

  final repository = LocalChatRepository(
    currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final conversationsProvider = FutureProvider<List<Conversation>>((ref) {
  ref.keepAlive();
  return ref.watch(chatRepositoryProvider).loadConversations();
});

/// Без автоповтора Riverpod: переподключением и опросом занимается сама
/// лента (liveFeed). Второй слой повторов только плодил бы лишние
/// подписки на каждую ошибку сети.
final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>(
      (ref, conversationId) =>
          ref.watch(chatRepositoryProvider).watchMessages(conversationId),
      retry: (_, _) => null,
    );

/// Карточка одного чата: заголовок, тип, права. Пустой личный диалог в
/// общем списке не виден, поэтому берётся отдельным запросом.
final conversationProvider = FutureProvider.autoDispose
    .family<Conversation, String>((ref, conversationId) {
      return ref.watch(chatRepositoryProvider).loadConversation(conversationId);
    });

final chatMembersProvider = FutureProvider.autoDispose
    .family<List<ChatMember>, String>((ref, conversationId) {
      return ref.watch(chatRepositoryProvider).loadMembers(conversationId);
    });

/// Открыта панель эмодзи (она стоит на месте клавиатуры, и системных
/// отступов снизу у неё нет). Пока так, оболочка прячет нижнюю навигацию.
/// Не провайдер: поле сбрасывает флаг в dispose, где ref уже недоступен.
final chatEmojiPanelOpen = ValueNotifier<bool>(false);

/// Отложенные сообщения чата: что и когда уйдёт.
final scheduledMessagesProvider = FutureProvider.autoDispose
    .family<List<ScheduledMessage>, String>(
      (ref, conversationId) =>
          ref.watch(chatRepositoryProvider).loadScheduled(conversationId),
      retry: (_, _) => null,
    );
