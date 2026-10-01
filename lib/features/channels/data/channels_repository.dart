import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/domain/entities/chat_message.dart';
import '../../chat/domain/entities/chat_meta.dart';

/// Темы каталога. Совпадают с check в миграции 0039.
enum ChannelTopic {
  news('news', 'Новости'),
  science('science', 'Наука'),
  fashion('fashion', 'Мода'),
  food('food', 'Еда'),
  memes('memes', 'Мемы'),
  city('city', 'Город'),
  travel('travel', 'Путешествия'),
  movies('movies', 'Кино'),
  sport('sport', 'Спорт'),
  other('other', 'Другое');

  const ChannelTopic(this.wire, this.label);
  final String wire;
  final String label;

  static ChannelTopic parse(Object? raw) =>
      values.firstWhere((t) => t.wire == raw, orElse: () => other);
}

class ChannelInfo {
  const ChannelInfo({
    required this.id,
    required this.title,
    required this.isPublic,
    required this.topic,
    required this.showSubscribers,
    this.description,
    this.handle,
    this.avatarUrl,
    this.subscriberCount,
    this.myRole,
    this.requested = false,
    this.inviteToken,
    this.pendingRequests = 0,
  });

  final String id;
  final String title;
  final String? description;
  final String? handle;
  final bool isPublic;
  final ChannelTopic topic;
  final String? avatarUrl;
  final bool showSubscribers;

  /// null — владелец скрыл число подписчиков.
  final int? subscriberCount;

  /// owner / admin / member; null — не подписан.
  final String? myRole;
  final bool requested;

  /// Только для админов.
  final String? inviteToken;
  final int pendingRequests;

  bool get isMember => myRole != null;
  bool get isOwner => myRole == 'owner';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';

  /// Посты видны: публичный канал или подписка.
  bool get canRead => isPublic || isMember;

  factory ChannelInfo.fromRow(Map<String, dynamic> row) => ChannelInfo(
    id: row['id'] as String,
    title: row['title'] as String? ?? 'Канал',
    description: row['description'] as String?,
    handle: row['handle'] as String?,
    isPublic: row['visibility'] == 'public',
    topic: ChannelTopic.parse(row['topic']),
    avatarUrl: row['avatar_url'] as String?,
    showSubscribers: row['show_subscribers'] as bool? ?? true,
    subscriberCount: (row['subscriber_count'] as num?)?.toInt(),
    myRole: row['my_role'] as String?,
    requested: row['requested'] as bool? ?? false,
    inviteToken: row['invite_token'] as String?,
    pendingRequests: (row['pending_requests'] as num?)?.toInt() ?? 0,
  );
}

class CatalogChannel {
  const CatalogChannel({
    required this.id,
    required this.title,
    required this.topic,
    required this.joined,
    this.description,
    this.handle,
    this.subscriberCount,
    this.lastPostAt,
  });

  final String id;
  final String title;
  final String? description;
  final String? handle;
  final ChannelTopic topic;
  final int? subscriberCount;
  final bool joined;
  final DateTime? lastPostAt;
}

/// Пост канала: сообщение + число комментариев.
class ChannelPost {
  const ChannelPost({required this.message, required this.commentCount});

  final ChatMessage message;
  final int commentCount;

  ChannelPost withComments(int count) =>
      ChannelPost(message: message, commentCount: count);
}

class JoinRequest {
  const JoinRequest({required this.profileId, required this.name, this.avatarUrl});

  final String profileId;
  final String name;
  final String? avatarUrl;
}

enum JoinResult { joined, requested }

class ChannelsRepository {
  ChannelsRepository(this._client);

  final SupabaseClient _client;

  Future<ChannelInfo?> info(String channelId) async {
    final rows = await _client.rpc('channel_info', params: {'in_channel': channelId}) as List;
    return rows.isEmpty ? null : ChannelInfo.fromRow(rows.first as Map<String, dynamic>);
  }

  Future<List<ChannelPost>> posts(String channelId, {DateTime? before}) async {
    final rows = await _client.rpc(
      'channel_posts',
      params: {
        'in_channel': channelId,
        'in_before': before?.toUtc().toIso8601String(),
      },
    ) as List;
    return [
      for (final raw in rows.cast<Map<String, dynamic>>())
        ChannelPost(
          commentCount: (raw['comment_count'] as num?)?.toInt() ?? 0,
          message: ChatMessage(
            id: raw['id'] as String,
            conversationId: channelId,
            senderId: raw['sender_id'] as String,
            sentAt: DateTime.parse(raw['sent_at'] as String).toLocal(),
            kind: MessageKind.parse(raw['kind']),
            text: raw['body'] as String?,
            attachment: ChatAttachment.fromJson(raw['media']),
            forwardedFrom: ChatMeta.fromJson(raw['meta']).forwardedFrom,
          ),
        ),
    ];
  }

  Future<List<CatalogChannel>> search({String? query, ChannelTopic? topic}) async {
    final rows = await _client.rpc(
      'search_channels',
      params: {'in_query': query, 'in_topic': topic?.wire},
    ) as List;
    return [
      for (final raw in rows.cast<Map<String, dynamic>>())
        CatalogChannel(
          id: raw['id'] as String,
          title: raw['title'] as String? ?? 'Канал',
          description: raw['description'] as String?,
          handle: raw['handle'] as String?,
          topic: ChannelTopic.parse(raw['topic']),
          subscriberCount: (raw['subscriber_count'] as num?)?.toInt(),
          joined: raw['joined'] as bool? ?? false,
          lastPostAt: raw['last_post_at'] == null
              ? null
              : DateTime.parse(raw['last_post_at'] as String).toLocal(),
        ),
    ];
  }

  Future<String> create({
    required String title,
    required String description,
    required bool isPublic,
    required ChannelTopic topic,
    String? handle,
  }) async =>
      await _client.rpc(
            'create_channel',
            params: {
              'in_title': title,
              'in_description': description,
              'in_visibility': isPublic ? 'public' : 'private',
              'in_handle': handle,
              'in_topic': topic.wire,
            },
          )
          as String;

  Future<void> update(
    ChannelInfo channel, {
    required String title,
    required String description,
    required bool isPublic,
    required String? handle,
    required ChannelTopic topic,
    required bool showSubscribers,
  }) => _client.rpc(
    'update_channel',
    params: {
      'in_channel': channel.id,
      'in_title': title,
      'in_description': description,
      'in_visibility': isPublic ? 'public' : 'private',
      'in_handle': handle,
      'in_topic': topic.wire,
      'in_show_subscribers': showSubscribers,
    },
  );

  Future<JoinResult> join(String channelId, {String? inviteToken}) async {
    final result = await _client.rpc(
      'channel_join',
      params: {'in_channel': channelId, 'in_token': inviteToken},
    );
    return result == 'requested' ? JoinResult.requested : JoinResult.joined;
  }

  Future<void> leave(String channelId) => _client.rpc(
    'remove_chat_member',
    params: {
      'in_conversation': channelId,
      'in_profile': _client.auth.currentUser!.id,
    },
  );

  Future<String> regenerateInvite(String channelId) async =>
      await _client.rpc('regenerate_channel_invite', params: {'in_channel': channelId})
          as String;

  Future<List<JoinRequest>> requests(String channelId) async {
    final rows = await _client.rpc('channel_requests', params: {'in_channel': channelId}) as List;
    return [
      for (final raw in rows.cast<Map<String, dynamic>>())
        JoinRequest(
          profileId: raw['profile_id'] as String,
          name: raw['display_name'] as String? ?? 'Без имени',
          avatarUrl: raw['avatar_url'] as String?,
        ),
    ];
  }

  Future<void> decide(String channelId, String profileId, {required bool approve}) =>
      _client.rpc(
        'decide_channel_request',
        params: {'in_channel': channelId, 'in_profile': profileId, 'in_approve': approve},
      );

  /// Отметка «прочитано до сих пор» — сбрасывает счётчик в списке чатов.
  Future<void> markRead(String channelId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client
        .from('chat_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .match({'conversation_id': channelId, 'profile_id': me});
  }
}
