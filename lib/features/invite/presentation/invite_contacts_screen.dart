import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../data/contacts_match.dart';

/// Прямая ссылка на файл последней сборки: открыл — пошло скачивание.
const _downloadUrl =
    'https://api-socialworld.deepdrift.tech/updates/chawo.apk';

enum _Phase { intro, loading, ready, denied, failed }

/// Отдаёт ли VK номер телефона при входе. Пока право `phone` не одобрено в
/// кабинете VK ID (и не добавлено в scope в oauth-vk-start), кнопка «Подтвердить
/// через VK» ничего не меняла бы, поэтому её нет. Одобрили — поставить true.
const vkReturnsPhone = false;

/// Приглашение из записной книжки: сверху те, кто уже в ChaWo, ниже — остальные
/// контакты с кнопкой «Пригласить». Номера контактов на сервер не уходят,
/// только их хеши.
class InviteContactsScreen extends ConsumerStatefulWidget {
  const InviteContactsScreen({super.key});

  @override
  ConsumerState<InviteContactsScreen> createState() =>
      _InviteContactsScreenState();
}

class _InviteContactsScreenState extends ConsumerState<InviteContactsScreen>
    with WidgetsBindingObserver {
  final _repo = ContactsMatchRepository(Supabase.instance.client);
  final _search = TextEditingController();

  var _phase = _Phase.intro;
  var _permanentlyDenied = false;
  var _phone = PhoneStatus.verified;
  ContactsMatch? _result;
  final _followed = <String>{};
  final _following = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  /// Вернулись из браузера после «Подтвердить через…»: номер мог прийти.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _phase != _Phase.ready) return;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      try {
        final phone = await _repo.phoneStatus();
        if (mounted) setState(() => _phone = phone);
      } catch (error) {
        AppLog.add('Статус номера: $error');
      }
    });
  }

  /// Если доступ уже выдан раньше — сразу показываем список, без вступления.
  Future<void> _autoStart() async {
    try {
      final status = await FlutterContacts.permissions.check(
        PermissionType.read,
      );
      if (status == PermissionStatus.granted ||
          status == PermissionStatus.limited) {
        await _load();
      }
    } catch (error) {
      AppLog.add('Проверка доступа к контактам: $error');
    }
  }

  Future<void> _allowAndLoad() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status == PermissionStatus.granted ||
        status == PermissionStatus.limited) {
      await _load();
    } else if (mounted) {
      setState(() {
        _permanentlyDenied = status == PermissionStatus.permanentlyDenied;
        _phase = _Phase.denied;
      });
    }
  }

  Future<void> _load() async {
    setState(() => _phase = _Phase.loading);
    try {
      final raw = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );
      final contacts = <PhoneContact>[];
      for (final contact in raw) {
        final name = contact.displayName?.trim() ?? '';
        final numbers = <String>[];
        final hashes = <String>{};
        for (final phone in contact.phones) {
          final normalized = normalizePhone(phone.number);
          if (normalized == null) continue;
          numbers.add(phone.number);
          hashes.add(hashPhone(normalized));
        }
        if (name.isEmpty || hashes.isEmpty) continue;
        contacts.add(
          PhoneContact(
            name: name,
            phones: numbers,
            hashes: hashes.toList(),
          ),
        );
      }
      contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final result = await _repo.match(contacts);
      final phone = await _repo.phoneStatus();
      if (!mounted) return;
      setState(() {
        _result = result;
        _phone = phone;
        _phase = _Phase.ready;
      });
    } catch (error) {
      AppLog.add('Контакты не загрузились: $error');
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _invite(PhoneContact contact) async {
    final body = Uri.encodeComponent(
      'Я в ChaWo — присоединяйся! Приложение для Android: $_downloadUrl',
    );
    final uri = Uri.parse('sms:${contact.phones.first}?body=$body');
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть сообщения')),
      );
    }
  }

  Future<void> _follow(KnownContact contact) async {
    setState(() => _following.add(contact.userId));
    try {
      await ref
          .read(profileRepositoryProvider)
          .setFollow(contact.userId, follow: true);
      if (mounted) setState(() => _followed.add(contact.userId));
    } catch (error) {
      AppLog.add('Подписка из контактов не прошла: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Не удалось подписаться'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _following.remove(contact.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пригласить из контактов'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: switch (_phase) {
        _Phase.intro => StateMessage(
          icon: Icons.contacts_outlined,
          title: 'Найдите друзей в ChaWo',
          text:
              'Покажем, кто из вашей записной книжки уже здесь, и поможем '
              'позвать остальных. Номера контактов на сервер не отправляются '
              '— сверка идёт по хешам.',
          actionLabel: 'Разрешить доступ к контактам',
          onAction: _allowAndLoad,
        ),
        _Phase.loading => const LoadingView(),
        _Phase.denied => StateMessage(
          icon: Icons.lock_outline,
          title: 'Нет доступа к контактам',
          text: _permanentlyDenied
              ? 'Разрешите доступ к контактам в настройках приложения.'
              : 'Без доступа список не собрать.',
          actionLabel: _permanentlyDenied ? 'Открыть настройки' : 'Попробовать снова',
          onAction: _permanentlyDenied
              ? () => FlutterContacts.permissions.openSettings()
              : _allowAndLoad,
        ),
        _Phase.failed => StateMessage.error(onAction: _load),
        _Phase.ready => _buildList(context),
      },
    );
  }

  /// Номер и его подтверждение живут в разделе «Безопасность»; здесь только
  /// подсказка, зачем он нужен для поиска друзей.
  Widget _phoneBanner() {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push(Routes.security),
      child: Row(
        children: [
          Icon(Icons.phone_outlined, color: AppColors.primaryTint),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _phone == PhoneStatus.none
                  ? 'Добавьте свой номер, чтобы друзья из их записных книжек '
                        'нашли вас в ChaWo. Это в разделе «Безопасность».'
                  : 'Номер не подтверждён. Подтвердить его можно в разделе «Безопасность».',
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final result = _result!;
    final query = _search.text.trim().toLowerCase();
    bool matches(String name) => query.isEmpty || name.toLowerCase().contains(query);

    final known = [
      for (final c in result.known)
        if (matches(c.contactName) || matches(c.displayName)) c,
    ];
    final others = [
      for (final c in result.others)
        if (matches(c.name)) c,
    ];

    return ListView(
      padding: AppSpacing.page(context, top: 8),
      children: [
        if (_phone != PhoneStatus.verified) ...[
          _phoneBanner(),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Поиск по контактам',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        if (known.isNotEmpty) ...[
          SectionLabel('Уже в ChaWo · ${known.length}'),
          const SizedBox(height: 4),
          for (final contact in known) _knownTile(contact),
          const SizedBox(height: 16),
        ],
        SectionLabel('Пригласить · ${others.length}'),
        const SizedBox(height: 4),
        if (others.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              query.isEmpty
                  ? 'В записной книжке нет контактов с номерами.'
                  : 'Ничего не нашлось.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final contact in others)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(name: contact.name),
            title: Text(contact.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(contact.phones.first),
            trailing: OutlinedButton(
              style: AppButtons.compact,
              onPressed: () => _invite(contact),
              child: const Text('Пригласить'),
            ),
          ),
      ],
    );
  }

  Widget _knownTile(KnownContact contact) {
    final followed = contact.followedByMe || _followed.contains(contact.userId);
    final busy = _following.contains(contact.userId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openProfile(context, contact.userId),
      leading: UserAvatar(name: contact.displayName, url: contact.avatarUrl),
      title: Text(contact.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: contact.contactName == contact.displayName
          ? null
          : Text('В контактах: ${contact.contactName}'),
      trailing: followed
          ? Text('Вы подписаны', style: Theme.of(context).textTheme.bodySmall)
          : FilledButton.tonal(
              style: AppButtons.compact,
              onPressed: busy ? null : () => _follow(contact),
              child: const Text('Подписаться'),
            ),
    );
  }
}
