import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/user_avatar.dart';
import '../../domain/profile_models.dart';
import '../providers/profile_providers.dart';

/// Что набрано после «@» прямо перед курсором; null — курсор не на упоминании.
/// «@» засчитывается в начале текста или после пробела/знака (не в почте).
String? mentionQueryAt(TextEditingValue value) {
  final cursor = value.selection.baseOffset;
  if (cursor < 0 || cursor > value.text.length) return null;
  final before = value.text.substring(0, cursor);
  final match = RegExp(r'(?:^|[^A-Za-z0-9_@])@([A-Za-z0-9_]{0,20})$').firstMatch(before);
  return match?.group(1);
}

/// Подставить «@ник » на место набранного после «@» и поставить курсор за ним.
TextEditingValue insertMention(TextEditingValue value, String username) {
  final cursor = value.selection.baseOffset;
  final before = value.text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  final after = value.text.substring(cursor);
  final inserted = '@$username ';
  final text = before.substring(0, at) + inserted + (after.startsWith(' ') ? after.substring(1) : after);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: at + inserted.length),
  );
}

/// Подсказки людей, пока человек набирает «@ник» в поле [controller]: лента
/// аватаров с именем и ником, тап — ник встаёт в текст. Отмеченные получат
/// уведомление (сервер находит @ник в тексте поста или блика).
class MentionSuggestions extends ConsumerStatefulWidget {
  const MentionSuggestions({super.key, required this.controller, this.dark = false});

  final TextEditingController controller;

  /// На тёмном фоне (редактор блика) — светлый текст.
  final bool dark;

  @override
  ConsumerState<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends ConsumerState<MentionSuggestions> {
  String? _query;
  List<ProfileHit> _hits = const [];
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _debounce?.cancel();
    super.dispose();
  }

  void _onText() {
    final query = mentionQueryAt(widget.controller.value);
    if (query == _query) return;
    _query = query;
    _debounce?.cancel();
    if (query == null) {
      if (_hits.isNotEmpty) setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(query));
  }

  Future<void> _search(String query) async {
    final request = ++_request;
    List<ProfileHit> hits;
    try {
      // Поиск по нику с «@»: так сервер ищет только по нику, не по имени.
      // Один символ — ещё рано, сервер ищет от двух.
      hits = query.isEmpty
          ? const []
          : await ref.read(profileRepositoryProvider).searchProfiles('@$query');
    } catch (_) {
      hits = const [];
    }
    if (!mounted || request != _request) return;
    setState(() => _hits = [for (final h in hits) if (h.username != null) h]);
  }

  void _pick(ProfileHit hit) {
    widget.controller.value = insertMention(widget.controller.value, hit.username!);
    setState(() {
      _hits = const [];
      _query = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hits.isEmpty) return const SizedBox.shrink();
    final color = widget.dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      key: const Key('mention-suggestions'),
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _hits.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final hit = _hits[i];
          return InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => _pick(hit),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(name: hit.displayName, url: hit.avatarUrl, radius: 16),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hit.displayName, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                      Text('@${hit.username}', style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
