import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Номер → то, что уходит на сервер. Только цифры, российский формат
/// приводится к 7XXXXXXXXXX: «8 (900) 123-45-67», «+7 900 123 45 67» и
/// «9001234567» дают один и тот же хеш. Слишком короткое и слишком длинное
/// — null.
String? normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('8')) {
    digits = '7${digits.substring(1)}';
  } else if (digits.length == 10) {
    digits = '7$digits';
  }
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

String hashPhone(String normalized) =>
    sha256.convert(utf8.encode(normalized)).toString();

/// Контакт записной книжки с уже посчитанными хешами всех его номеров.
class PhoneContact {
  const PhoneContact({
    required this.name,
    required this.phones,
    required this.hashes,
  });

  final String name;

  /// Номера в том виде, как записаны в книжке (для SMS).
  final List<String> phones;
  final List<String> hashes;
}

/// Человек, который уже в ChaWo.
class KnownContact {
  const KnownContact({
    required this.contactName,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.followedByMe = false,
  });

  final String contactName;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool followedByMe;
}

class ContactsMatch {
  const ContactsMatch({required this.known, required this.others});

  final List<KnownContact> known;
  final List<PhoneContact> others;
}

class ContactsMatchRepository {
  ContactsMatchRepository(this._client);

  final SupabaseClient _client;

  static const _chunk = 1000;

  Future<bool> hasMyPhone() async =>
      (await _client.rpc('has_my_phone')) as bool? ?? false;

  /// Бросает [FormatException], если номер не похож на номер.
  Future<void> setMyPhone(String raw) async {
    final normalized = normalizePhone(raw);
    if (normalized == null) throw const FormatException('некорректный номер');
    await _client.rpc('set_my_phone', params: {'p_hash': hashPhone(normalized)});
  }

  Future<void> clearMyPhone() => _client.rpc('clear_my_phone');

  /// Делит контакты на «уже в ChaWo» и «можно пригласить».
  Future<ContactsMatch> match(List<PhoneContact> contacts) async {
    final owners = <String, PhoneContact>{};
    for (final contact in contacts) {
      for (final hash in contact.hashes) {
        owners[hash] = contact;
      }
    }

    final hashes = owners.keys.toList();
    final hits = <String, Map<String, dynamic>>{};
    for (var i = 0; i < hashes.length; i += _chunk) {
      final part = hashes.sublist(
        i,
        i + _chunk > hashes.length ? hashes.length : i + _chunk,
      );
      final rows = await _client.rpc('match_contacts', params: {'p_hashes': part});
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        hits[row['phone_hash'] as String] = row;
      }
    }

    final known = <KnownContact>[];
    final knownUsers = <String>{};
    final matchedContacts = <PhoneContact>{};
    for (final entry in hits.entries) {
      final contact = owners[entry.key]!;
      matchedContacts.add(contact);
      final row = entry.value;
      final userId = row['id'] as String;
      if (!knownUsers.add(userId)) continue;
      known.add(
        KnownContact(
          contactName: contact.name,
          userId: userId,
          displayName: row['display_name'] as String? ?? contact.name,
          avatarUrl: row['avatar_url'] as String?,
          followedByMe: row['followed_by_me'] as bool? ?? false,
        ),
      );
    }

    final others = [
      for (final contact in contacts)
        if (!matchedContacts.contains(contact)) contact,
    ];
    return ContactsMatch(known: known, others: others);
  }
}
