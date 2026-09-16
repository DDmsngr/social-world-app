import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local_chat_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  // keepAlive: у заглушки переписка лежит в памяти, пересоздание стёрло бы её.
  ref.keepAlive();
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

final messagesProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatRepositoryProvider).watchMessages(conversationId);
});
