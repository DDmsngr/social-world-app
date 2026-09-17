import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  bool _checking = false;

  // Проверяем и обычный интернет, и конкретно домены Яндекс.Карт: если
  // ya.ru отвечает, а карточные хосты — нет, дело не в интернете вообще,
  // а именно в доступе к MapKit (ключ/блокировка/регион).
  static const _urls = [
    'https://ya.ru',
    'https://core-renderer-tiles.maps.yandex.net/',
    'https://api-maps.yandex.ru/',
  ];

  Future<void> _runNetworkCheck() async {
    setState(() => _checking = true);
    AppLog.add('--- проверка сети: старт ---');
    for (final url in _urls) {
      final sw = Stopwatch()..start();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        await response.drain<void>();
        AppLog.add('GET $url -> ${response.statusCode} (${sw.elapsedMilliseconds}мс)');
      } catch (e) {
        AppLog.add('GET $url -> ОШИБКА: $e (${sw.elapsedMilliseconds}мс)');
      } finally {
        client.close(force: true);
      }
    }
    AppLog.add('--- проверка сети: конец ---');
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: AppLog.entries.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Логи скопированы')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(AppLog.clear),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            onPressed: _copyAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _checking ? null : _runNetworkCheck,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Проверить сеть'),
            ),
          ),
          Expanded(
            child: AppLog.entries.isEmpty
                ? const Center(child: Text('Пока пусто'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: AppLog.entries.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        AppLog.entries[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
