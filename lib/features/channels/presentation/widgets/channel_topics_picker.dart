import 'package:flutter/material.dart';

import '../../data/channels_repository.dart';

/// Сколько тем у канала (совпадает с check в миграции 0075).
const maxChannelTopics = 5;

/// Темы канала: нажмите на готовые (можно несколько) или впишите свою.
/// Свои темы — слова от 2 до 24 знаков: «настолки», «кофе в Сочи».
class ChannelTopicsPicker extends StatefulWidget {
  const ChannelTopicsPicker({super.key, required this.topics, required this.onChanged});

  final List<String> topics;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ChannelTopicsPicker> createState() => _ChannelTopicsPickerState();
}

class _ChannelTopicsPickerState extends State<ChannelTopicsPicker> {
  final _own = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  bool get _full => widget.topics.length >= maxChannelTopics;

  bool _has(String topic) =>
      widget.topics.any((t) => t.toLowerCase() == topic.toLowerCase());

  void _toggleBuiltin(ChannelTopic topic) {
    final next = [...widget.topics];
    if (_has(topic.wire)) {
      next.removeWhere((t) => t.toLowerCase() == topic.wire);
    } else if (!_full) {
      next.add(topic.wire);
    }
    setState(() => _error = null);
    widget.onChanged(next);
  }

  void _addOwn() {
    final text = _own.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return;
    if (text.length < 2 || text.length > 24) {
      setState(() => _error = 'Тема: от 2 до 24 знаков');
      return;
    }
    if (_has(text)) {
      setState(() => _error = 'Такая тема уже есть');
      return;
    }
    if (_full) {
      setState(() => _error = 'Не больше $maxChannelTopics тем');
      return;
    }
    _own.clear();
    setState(() => _error = null);
    widget.onChanged([...widget.topics, text]);
  }

  @override
  Widget build(BuildContext context) {
    final builtin = {for (final t in ChannelTopic.values) t.wire};
    final custom = [for (final t in widget.topics) if (!builtin.contains(t)) t];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Темы (до $maxChannelTopics): ${widget.topics.length}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final topic in ChannelTopic.values)
              FilterChip(
                label: Text(topic.label),
                selected: _has(topic.wire),
                onSelected: (_) => _toggleBuiltin(topic),
              ),
            for (final topic in custom)
              InputChip(
                label: Text(topic),
                selected: true,
                onDeleted: () {
                  setState(() => _error = null);
                  widget.onChanged([...widget.topics]..remove(topic));
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _own,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addOwn(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: 'Своя тема',
                  counterText: '',
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _addOwn,
              tooltip: 'Добавить тему',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
