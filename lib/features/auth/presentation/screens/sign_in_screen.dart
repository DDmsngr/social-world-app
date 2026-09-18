import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/dev_mode.dart';
import '../../../../core/config/env.dart';
import '../../../../core/dev/dev_sign_in_panel.dart';
import '../../../../core/oauth/oauth_sign_in.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../data/local_auth_repository.dart';
import '../providers/auth_providers.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _devCode;

  // 406-ФЗ: для боевого продукта в РФ основной вход — VK ID/Яндекс ID,
  // почта — служебный резервный путь, скрытый со стартового экрана.
  bool _showEmailFlow = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Почта — служебный резервный путь: показываем её либо по запросу
  // пользователя, либо когда бэкенд не настроен (дев-режим без Supabase).
  bool get _emailVisible => _showEmailFlow || !Env.isConfigured;

  String _subtitle() {
    if (!_emailVisible) {
      return 'Войдите через VK ID или Яндекс ID — это быстро и без пароля.';
    }
    if (!_codeSent) {
      return 'Войдите по почте — пароль не нужен, пришлём одноразовый код.';
    }
    // Врать, что письмо ушло, нельзя — почты за заглушкой нет.
    return _devCode != null
        ? 'Почта пока не подключена, код подставлен ниже.'
        : 'Отправили код на ${_emailController.text.trim()}';
  }

  String _readable(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.isEmpty ? 'Что-то пошло не так, попробуйте ещё раз' : text;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(authRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const SectionLabel('Social World'),
              const SizedBox(height: 16),
              Text('Город,\nкоторый вас ', style: AppTypography.serif(40)),
              Text(
                'узнаёт.',
                style: AppTypography.serif(
                  40,
                  color: AppColors.primaryTint,
                  style: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _subtitle(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              // Основной вход в РФ обязан быть через VK ID/Яндекс ID или
              // телефон (406-ФЗ) — почта только по явному запросу пользователя.
              if (!_emailVisible) ...[
                OutlinedButton(
                  onPressed: () => startOAuthSignIn(OAuthBridgeProvider.vk),
                  child: const Text('Войти через VK ID'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () =>
                      startOAuthSignIn(OAuthBridgeProvider.yandex),
                  child: const Text('Войти через Яндекс ID'),
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showEmailFlow = true),
                    child: const Text('Войти по почте'),
                  ),
                ),
              ] else ...[
                // Ключи обязательны: оба поля стоят в одной позиции дерева, и
                // без них Flutter переиспользует состояние — в поле кода
                // остаётся текст почты, а контроллер расходится с тем, что
                // видно.
                if (!_codeSent)
                  TextField(
                    key: const ValueKey('sign-in-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'почта'),
                  )
                else
                  TextField(
                    key: const ValueKey('sign-in-code'),
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 22, letterSpacing: 8),
                    decoration: const InputDecoration(
                      hintText: '______',
                      counterText: '',
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            if (!_codeSent) {
                              await repo
                                  .requestEmailCode(_emailController.text);
                              if (!mounted) return;
                              // Письма нет — подставляем выданный код сами,
                              // чтобы не переписывать его руками из панели.
                              final issued = repo is LocalAuthRepository
                                  ? repo.issuedCode
                                  : null;
                              setState(() {
                                _codeSent = true;
                                _devCode = issued;
                                if (issued != null) {
                                  _codeController.text = issued;
                                }
                              });
                            } else {
                              await repo.verifyEmailCode(
                                email: _emailController.text,
                                code: _codeController.text,
                              );
                            }
                          }),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : Text(_codeSent ? 'Войти' : 'Получить код'),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _devCode = null;
                              _codeController.clear();
                            }),
                    child: const Text('Другая почта'),
                  ),
                if (Env.isConfigured && !_codeSent)
                  TextButton(
                    onPressed: () =>
                        setState(() => _showEmailFlow = false),
                    child: const Text('Назад к VK ID / Яндекс ID'),
                  ),
              ],
              const Spacer(),
              if (DevMode.enabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DevSignInPanel(issuedCode: _devCode),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
