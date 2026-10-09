import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:social_world/core/config/env.dart';
import 'package:social_world/core/oauth/oauth_sign_in.dart';

class _MemoryStore implements PendingOAuthStore {
  String? secret;
  DateTime? at;

  @override
  Future<void> save(String secret, DateTime at) async {
    this.secret = secret;
    this.at = at;
  }

  @override
  Future<String?> take(DateTime now, Duration ttl) async {
    final s = secret;
    final saved = at;
    secret = null;
    at = null;
    if (s == null || saved == null) return null;
    final age = now.difference(saved);
    return (!age.isNegative && age <= ttl) ? s : null;
  }
}

void main() {
  setUpAll(() => Env.loadForTest({
        'SUPABASE_URL': 'https://api.example.test',
        'SUPABASE_ANON_KEY': 'sb_publishable_test',
      }));

  group('OAuthSecret', () {
    test('секрет — 43 знака base64url без «=», каждый раз новый', () {
      final a = OAuthSecret.generate(Random(1));
      final b = OAuthSecret.generate(Random(2));
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(a, isNot(b));
    });

    test('хеш совпадает с эталоном SHA-256 (то, что считает сервер)', () {
      // sha256("abc") = ba7816bf…, base64url без паддинга.
      expect(
        OAuthSecret.challengeOf('abc'),
        'ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0',
      );
      expect(OAuthSecret.challengeOf('abc'), matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    });
  });

  group('SecurePendingOAuthStore / память: срок и одна попытка', () {
    test('свежий секрет отдаётся один раз', () async {
      final store = _MemoryStore();
      final t0 = DateTime(2026, 10, 8, 12);
      await store.save('s3cret', t0);
      expect(await store.take(t0.add(const Duration(minutes: 1)), oauthPendingTtl), 's3cret');
      expect(await store.take(t0.add(const Duration(minutes: 1)), oauthPendingTtl), isNull);
    });

    test('протухший секрет не отдаётся', () async {
      final store = _MemoryStore();
      final t0 = DateTime(2026, 10, 8, 12);
      await store.save('s3cret', t0);
      expect(await store.take(t0.add(const Duration(minutes: 11)), oauthPendingTtl), isNull);
    });
  });

  group('OAuthDeepLinkListener', () {
    late _MemoryStore store;
    late List<http.Request> requests;
    late List<String> applied;
    late OAuthDeepLinkListener listener;
    var statusCode = 200;
    var responseBody = jsonEncode({'access_token': 'a', 'refresh_token': 'refresh-1'});
    final now = DateTime(2026, 10, 8, 12);

    setUp(() {
      store = _MemoryStore();
      requests = [];
      applied = [];
      statusCode = 200;
      responseBody = jsonEncode({'access_token': 'a', 'refresh_token': 'refresh-1'});
      listener = OAuthDeepLinkListener(
        store: store,
        links: const Stream<Uri>.empty(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(responseBody, statusCode);
        }),
        applySession: (token) async => applied.add(token),
        now: () => now,
      );
    });

    tearDown(() => listener.dispose());

    test('чужая ссылка без начатого входа игнорируется: сервер не зовём', () async {
      await listener.handle(Uri.parse('socialworld://auth-callback?code=attacker-code'));
      expect(requests, isEmpty);
      expect(applied, isEmpty);
    });

    test('ссылка с токеном злоумышленника в старом формате не входит в аккаунт', () async {
      await store.save('my-secret', now);
      await listener.handle(
        Uri.parse('socialworld://auth-callback#access_token=x&refresh_token=evil'),
      );
      expect(applied, isEmpty);
      expect(requests, isEmpty);
    });

    test('начатый вход: код меняется на сессию вместе с секретом', () async {
      await store.save('my-secret', now);
      await listener.handle(Uri.parse('socialworld://auth-callback?code=good-code'));
      expect(requests, hasLength(1));
      expect(requests.single.url.toString(), 'https://api.example.test/functions/v1/oauth-exchange');
      expect(requests.single.headers['apikey'], 'sb_publishable_test');
      expect(jsonDecode(requests.single.body), {'code': 'good-code', 'secret': 'my-secret'});
      expect(applied, ['refresh-1']);
    });

    test('отказ сервера (чужой код) сессию не открывает', () async {
      statusCode = 400;
      responseBody = jsonEncode({'error': 'invalid_or_expired'});
      await store.save('my-secret', now);
      await listener.handle(Uri.parse('socialworld://auth-callback?code=attacker-code'));
      expect(requests, hasLength(1));
      expect(applied, isEmpty);
    });

    test('одна попытка на один вход: повторная ссылка не меняет код снова', () async {
      await store.save('my-secret', now);
      await listener.handle(Uri.parse('socialworld://auth-callback?code=good-code'));
      await listener.handle(Uri.parse('socialworld://auth-callback?code=good-code'));
      expect(requests, hasLength(1));
    });

    test('ссылки других адресов и схем не трогаем', () async {
      await store.save('my-secret', now);
      await listener.handle(Uri.parse('socialworld://post/123?code=x'));
      await listener.handle(Uri.parse('https://evil.test/auth-callback?code=x'));
      expect(requests, isEmpty);
      // секрет при этом не сгорел
      expect(await store.take(now, oauthPendingTtl), 'my-secret');
    });
  });
}
