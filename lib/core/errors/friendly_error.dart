import 'dart:async';

import '../permissions/content_permissions.dart';

/// Человеческий текст вместо сырого исключения. Экран показывает его в
/// snackbar; сырая причина при этом остаётся в AppLog.
String friendlyError(Object error, {String fallback = 'Что-то пошло не так'}) {
  if (error is PermissionDeniedException) return error.message;
  if (error is TimeoutException) return 'Сервер долго не отвечает';

  final text = error.toString();
  // Триггер enforce_rate_limit (миграция 0015) бросает 'rate_limit: …'.
  if (text.contains('rate_limit')) {
    return 'Слишком часто. Подождите немного и попробуйте снова';
  }
  if (text.contains('42501') || text.contains('row-level security')) {
    return 'Нет прав на это действие';
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection')) {
    return 'Нет связи с сервером';
  }
  return fallback;
}
