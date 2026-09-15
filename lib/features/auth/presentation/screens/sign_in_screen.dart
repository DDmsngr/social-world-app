import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
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
                  color: AppColors.clay,
                  style: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _codeSent
                    ? 'Отправили код на ${_emailController.text.trim()}'
                    : 'Войдите по почте — пароль не нужен, пришлём одноразовый код.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              if (!_codeSent)
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'почта'),
                )
              else
                TextField(
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
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
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
                            if (mounted) setState(() => _codeSent = true);
                          } else {
                            await repo.verifyEmailCode(
                              email: _emailController.text,
                              code: _codeController.text,
                            );
                          }
                        }),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.ink,
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
                            _codeController.clear();
                          }),
                  child: const Text('Другая почта'),
                ),
              const Spacer(),
              if (!Env.isConfigured)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Бэкенд не подключён — вход работает локально, '
                    'код подтверждения любой из шести цифр.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12, color: AppColors.sage),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
