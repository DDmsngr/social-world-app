import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/channels/presentation/channel_article_screen.dart';

void main() {
  testWidgets('в редакторе статьи одна кнопка «назад» и видны заголовок с публикацией', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<bool>(builder: (_) => const ChannelArticleScreen(channelId: 'c')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Статья в канал'), findsOneWidget);
    expect(find.text('Опубликовать'), findsOneWidget);
  });
}
