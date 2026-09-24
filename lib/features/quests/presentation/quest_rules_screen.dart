import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/entities/quest.dart';
import 'providers/quests_providers.dart';

/// Правила квестов перед первым созданием (п. 49). Согласие сохраняется на
/// сервере с версией и временем (п. 50). Возвращает true, если приняты.
///
/// Текст — из ТЗ дословно по смыслу. При существенном изменении поднять
/// [QuestRulesConsent.currentVersion] и `quest_rules_version()` в базе.
class QuestRulesScreen extends ConsumerStatefulWidget {
  const QuestRulesScreen({super.key});

  static Future<bool> open(BuildContext context) async {
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const QuestRulesScreen(), fullscreenDialog: true),
    );
    return accepted ?? false;
  }

  @override
  ConsumerState<QuestRulesScreen> createState() => _QuestRulesScreenState();
}

class _QuestRulesScreenState extends ConsumerState<QuestRulesScreen> {
  var _agreed = false;
  var _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(questsRepositoryProvider)
          .acceptRules(QuestRulesConsent.currentVersion);
      ref.invalidate(questRulesConsentProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось сохранить согласие'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Правила квестов')),
      body: ListView(
        padding: AppSpacing.page(context),
        children: [
          Text('Квесты — для обычной\nгородской жизни', style: AppTypography.serif(28)),
          const SizedBox(height: 16),
          Text(
            'Квесты предназначены для обычных городских активностей:',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          for (final item in const [
            'прогулки;',
            'спорт;',
            'развлечения;',
            'игры;',
            'посещение заведений;',
            'совместные активности;',
            'другие законные городские мероприятия.',
          ])
            bullet(item),
          const SizedBox(height: 14),
          Text('Запрещается использовать квесты для:', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final item in const [
            'политической агитации;',
            'политических акций;',
            'публичных митингов и шествий;',
            'незаконных действий;',
            'опасных массовых мероприятий;',
            'других активностей, нарушающих правила ChaWo или законодательство.',
          ])
            bullet(item),
          const SizedBox(height: 14),
          Text(
            'Организатор отвечает за достоверность информации и безопасность '
            'заявленной активности в пределах своей ответственности.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          CheckboxListTile(
            value: _agreed,
            onChanged: _busy ? null : (value) => setState(() => _agreed = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Я прочитал(а) и принимаю Правила квестов'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Отклонить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _agreed && !_busy ? _accept : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Принять'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
