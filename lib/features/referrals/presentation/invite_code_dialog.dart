import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Спрашивает код пригласившего (6–10 знаков, как у личной ссылки). Возвращает
/// код заглавными или null, если человек отказался или ввёл слишком мало.
///
/// Общий для двух мест: кнопка «Ввести код пригласившего» в профиле и вопрос
/// «Вас пригласили в ChaWo?» после регистрации.
Future<String?> askInviteCode(
  BuildContext context, {
  String title = 'Код пригласившего',
  String? message,
  String cancelLabel = 'Отмена',
}) async {
  final code = await showDialog<String>(
    context: context,
    builder: (_) => _InviteCodeDialog(title: title, message: message, cancelLabel: cancelLabel),
  );
  return code == null || code.length < 6 ? null : code.toUpperCase();
}

/// Контроллер живёт в состоянии диалога: пока тот закрывается, поле ещё
/// перерисовывается, и удалять контроллер снаружи нельзя.
class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog({required this.title, required this.message, required this.cancelLabel});

  final String title;
  final String? message;
  final String cancelLabel;

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('invite-code-field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
            decoration: const InputDecoration(hintText: 'ABC234', counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
