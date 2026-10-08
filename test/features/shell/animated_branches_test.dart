import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/shell/presentation/animated_branches.dart';

/// Считает, сколько раз вкладку создавали и убивали, и помнит нажатия.
class _Tab extends StatefulWidget {
  const _Tab(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  var taps = 0;
  var ticking = true;

  @override
  void initState() {
    super.initState();
    widget.log.add('init ${widget.name}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ticking = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    widget.log.add('dispose ${widget.name}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => taps++),
    child: ColoredBox(color: Colors.black, child: Center(child: Text('${widget.name}:$taps'))),
  );
}

void main() {
  late List<String> log;

  Widget app(int index) => MaterialApp(
    home: AnimatedBranches(
      currentIndex: index,
      children: [for (final name in ['feed', 'map', 'create']) _Tab(name, log)],
    ),
  );

  setUp(() => log = []);

  testWidgets('переключение вкладок ничего не пересоздаёт и не теряет состояние',
      (tester) async {
    await tester.pumpWidget(app(0));
    expect(log.where((l) => l.startsWith('init')).length, 3);

    await tester.tap(find.text('feed:0'));
    await tester.pump();
    expect(find.text('feed:1'), findsOneWidget);

    // Кругом по всем вкладкам, включая карту, и обратно.
    for (final index in [1, 2, 0, 1, 0, 2, 1, 0]) {
      await tester.pumpWidget(app(index));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();
    }

    expect(log.where((l) => l.startsWith('init')).length, 3, reason: 'создаются один раз');
    expect(log.where((l) => l.startsWith('dispose')), isEmpty, reason: 'не уничтожаются');
    expect(find.text('feed:1', skipOffstage: false), findsOneWidget, reason: 'состояние цело');
  });

  testWidgets('скрытая вкладка не принимает нажатий и не тикает, видна только текущая',
      (tester) async {
    await tester.pumpWidget(app(2));
    await tester.pumpAndSettle();

    expect(find.text('create:0'), findsOneWidget);
    expect(find.text('feed:0'), findsNothing, reason: 'скрытые не рисуются');
    expect(find.text('map:0'), findsNothing);

    final feedState = tester.state<_TabState>(find.byType(_Tab, skipOffstage: false).first);
    expect(feedState.ticking, isFalse, reason: 'у скрытой вкладки тикеры (и видео) выключены');
  });

  testWidgets('карта переключается мгновенно, остальные — плавно', (tester) async {
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();

    await tester.pumpWidget(app(1));
    await tester.pump(); // один кадр
    expect(find.text('map:0'), findsOneWidget, reason: 'карта сразу на экране');

    await tester.pumpWidget(app(2));
    await tester.pump();
    expect(find.text('create:0'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
