import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/oauth/oauth_sign_in.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../invite/data/contacts_match.dart';
import '../../invite/presentation/invite_contacts_screen.dart' show vkReturnsPhone;
import 'settings_screen.dart' show GeoPrivacy, LastSeenSwitch;

/// Безопасность и приватность: номер телефона и его подтверждение, способы
/// входа, кто видит вас и где вы, блокировки. Раньше это было россыпью по
/// настройкам и экрану приглашения из контактов.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Безопасность'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.settings),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: AppSpacing.page(context, top: AppSpacing.gutter),
        children: [
          const SectionLabel('Номер телефона'),
          const SizedBox(height: 12),
          if (Env.isConfigured)
            const _PhoneSection()
          else
            const GlassCard(child: Text('Номер доступен после входа в аккаунт.')),
          const SizedBox(height: 26),
          const SectionLabel('Вход в аккаунт'),
          const SizedBox(height: 12),
          if (Env.isConfigured) const _SignInSection(),
          const SizedBox(height: 26),
          const SectionLabel('Кто вас видит'),
          const SizedBox(height: 12),
          const LastSeenSwitch(),
          const SizedBox(height: 10),
          const GeoPrivacy(),
          const SizedBox(height: 26),
          const SectionLabel('Блокировки'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            onTap: () => context.push(Routes.blocked),
            child: Row(
              children: [
                Icon(Icons.block_outlined, color: AppColors.primaryTint),
                const SizedBox(width: 14),
                const Expanded(child: Text('Заблокированные и скрытые')),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionLabel('Шифрование'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: AppColors.primaryTint),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Личные переписки зашифрованы: сервер видит только шифротекст. '
                    'Чтобы убедиться, что вам пишет именно он, откройте меню чата и '
                    'сверьте «Код безопасности» с собеседником. Если у собеседника '
                    'сменится ключ, приложение предупредит и остановит отправку, пока '
                    'вы не примете новый.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Номер: свой для поиска друзьями или подтверждённый входом через провайдера.
class _PhoneSection extends StatefulWidget {
  const _PhoneSection();

  @override
  State<_PhoneSection> createState() => _PhoneSectionState();
}

class _PhoneSectionState extends State<_PhoneSection> with WidgetsBindingObserver {
  final _repo = ContactsMatchRepository(Supabase.instance.client);
  PhoneStatus? _status;
  var _providers = <String>{};
  var _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Вернулись из браузера после подтверждения: номер мог прийти.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    try {
      final status = await _repo.phoneStatus();
      final providers = await _repo.oauthProviders();
      if (!mounted) return;
      setState(() {
        _status = status;
        _providers = providers;
        _failed = false;
      });
    } catch (error) {
      AppLog.add('Статус номера: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Мой номер'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По номеру друзья из записной книжки смогут найти вас в ChaWo. '
              'Сам номер на сервере не хранится — только его защищённый хеш, и он '
              'никому не показывается.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(labelText: '+7 900 123-45-67'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || !mounted) return;
    try {
      await _repo.setMyPhone(entered);
      if (!mounted) return;
      setState(() => _status = PhoneStatus.self);
      _toast('Номер привязан');
    } on FormatException {
      if (mounted) _toast('Это не похоже на номер телефона');
    } catch (error) {
      AppLog.add('Номер не сохранился: $error');
      if (mounted) _toast(friendlyError(error, fallback: 'Не удалось сохранить номер'));
    }
  }

  Future<void> _remove() async {
    try {
      await _repo.clearMyPhone();
      if (mounted) setState(() => _status = PhoneStatus.none);
    } catch (error) {
      AppLog.add('Номер не удалился: $error');
      if (mounted) _toast(friendlyError(error, fallback: 'Не удалось убрать номер'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (_failed && status == null) {
      return GlassCard(
        onTap: _load,
        child: const Text('Не удалось загрузить. Нажмите, чтобы повторить.'),
      );
    }
    if (status == null) {
      return const GlassCard(child: Center(child: CircularProgressIndicator()));
    }

    final via = [
      if (_providers.contains('yandex')) (OAuthBridgeProvider.yandex, 'Яндекс'),
      if (_providers.contains('vk') && vkReturnsPhone) (OAuthBridgeProvider.vk, 'VK'),
    ];
    final vkOnly = _providers.contains('vk') && !vkReturnsPhone && via.isEmpty;

    final (icon, title, text) = switch (status) {
      PhoneStatus.verified => (
        Icons.verified_outlined,
        'Номер подтверждён',
        'Номер пришёл от провайдера входа, поэтому никто другой не сможет занять '
            'его в ChaWo. Он привязан ко входу и здесь не меняется.',
      ),
      PhoneStatus.self => (
        Icons.phone_outlined,
        'Номер указан вручную',
        vkOnly
            ? 'Он не подтверждён. Через VK подтвердить номер пока нельзя: VK не '
                  'передаёт его приложению, пока не одобрит доступ. Друзья вас находят и так.'
            : 'Он не подтверждён. Подтвердите его входом через Яндекс — тогда никто '
                  'не сможет занять ваш номер.',
      ),
      PhoneStatus.none => (
        Icons.phone_outlined,
        'Номер не указан',
        'Добавьте номер, чтобы друзья из их записных книжек нашли вас в ChaWo.',
      ),
    };

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryTint),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
          if (status != PhoneStatus.verified) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == PhoneStatus.self)
                  for (final (provider, name) in via)
                    FilledButton.tonal(
                      style: AppButtons.compact,
                      onPressed: () => startOAuthSignIn(provider),
                      child: Text('Подтвердить через $name'),
                    ),
                OutlinedButton(
                  style: AppButtons.compact,
                  onPressed: _edit,
                  child: Text(status == PhoneStatus.self ? 'Сменить номер' : 'Ввести номер'),
                ),
                if (status == PhoneStatus.self)
                  TextButton(
                    style: AppButtons.compact,
                    onPressed: _remove,
                    child: const Text('Убрать'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Какими способами человек входит: пароля у аккаунта нет, вход идёт через
/// Яндекс ID или VK ID.
class _SignInSection extends StatefulWidget {
  const _SignInSection();

  @override
  State<_SignInSection> createState() => _SignInSectionState();
}

class _SignInSectionState extends State<_SignInSection> {
  Set<String>? _providers;

  @override
  void initState() {
    super.initState();
    ContactsMatchRepository(Supabase.instance.client).oauthProviders().then((value) {
      if (mounted) setState(() => _providers = value);
    }).catchError((Object error) {
      AppLog.add('Способы входа: $error');
      if (mounted) setState(() => _providers = const {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (providers == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            for (final (key, name) in const [('yandex', 'Яндекс ID'), ('vk', 'VK ID')])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      providers.contains(key) ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20,
                      color: providers.contains(key) ? AppColors.primaryTint : AppColors.textFaint,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name)),
                    Text(
                      providers.contains(key) ? 'подключён' : 'не подключён',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textFaint),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Пароля у аккаунта нет: вход идёт через Яндекс ID или VK ID, поэтому '
              'пароль нельзя ни украсть, ни забыть.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
