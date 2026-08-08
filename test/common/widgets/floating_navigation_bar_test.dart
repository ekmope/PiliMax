import 'package:PiliMax/common/widgets/floating_navigation_bar.dart';
import 'package:PiliMax/common/widgets/liquid_glass_quality.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Widget> destinations() => const [
    FloatingNavigationDestination(
      icon: Icon(Icons.home_outlined),
      label: 'Home',
    ),
    FloatingNavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      label: 'Dynamic',
    ),
    FloatingNavigationDestination(
      icon: Icon(Icons.person_outline),
      label: 'Mine',
    ),
  ];

  Widget host({
    ValueChanged<int>? onSelected,
    int selectedIndex = 0,
    LiquidGlassQuality liquidGlassQuality = LiquidGlassQuality.reflective,
  }) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: _NavigationHost(
        initialIndex: selectedIndex,
        onSelected: onSelected,
        destinations: destinations(),
        liquidGlassQuality: liquidGlassQuality,
      ),
    );
  }

  testWidgets('liquid glass mode adds a clipped backdrop filter', (
    tester,
  ) async {
    await tester.pumpWidget(host(onSelected: (_) {}));

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(RawMagnifier), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('tap and horizontal drag select destinations', (tester) async {
    var selected = 0;
    final selections = <int>[];
    await tester.pumpWidget(
      host(
        onSelected: (value) {
          selected = value;
          selections.add(value);
        },
      ),
    );

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    expect(selected, 2);

    final mineCenter = tester.getCenter(find.text('Mine'));
    final gesture = await tester.startGesture(mineCenter);
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();

    final indicator = find.byKey(const ValueKey('liquidGlassIndicator'));
    expect(tester.getCenter(indicator).dx, lessThan(mineCenter.dx));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(selections, [2, 1]);
  });

  testWidgets('tapping the current destination still dispatches', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(
      host(onSelected: selections.add),
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(selections, [0]);
  });

  testWidgets('vertical drags cancel without changing destination', (
    tester,
  ) async {
    var selected = -1;
    await tester.pumpWidget(host(onSelected: (value) => selected = value));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Mine')),
    );
    await gesture.moveBy(const Offset(2, -64));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, -1);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('tapping a disabled destination is a no-op', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: FloatingNavigationBar(
            liquidGlass: true,
            destinations: const [
              FloatingNavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              FloatingNavigationDestination(
                icon: Icon(Icons.bolt_outlined),
                label: 'Dynamic',
                enabled: false,
              ),
              FloatingNavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Mine',
              ),
            ],
            onDestinationSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dynamic'));
    await tester.pumpAndSettle();

    expect(selected, -1);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('semantic selection callbacks do not lock later selections', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(host(onSelected: selections.add));

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    navigationBar.onDestinationSelected!(0);
    await tester.pump();
    navigationBar.onDestinationSelected!(1);
    await tester.pump();

    expect(selections, [0, 1]);
  });

  testWidgets('press moves and enlarges the glass lens before release', (
    tester,
  ) async {
    var selected = -1;
    await tester.pumpWidget(host(onSelected: (value) => selected = value));

    final indicator = find.byKey(const ValueKey('liquidGlassIndicator'));
    final idleWidth = tester.getSize(indicator).width;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Mine')),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(selected, -1);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(tester.getSize(indicator).width, greaterThan(idleWidth));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('pressed lens can flow outside the floating bar', (tester) async {
    await tester.pumpWidget(host(onSelected: (_) {}));

    final indicator = find.byKey(const ValueKey('liquidGlassIndicator'));
    final navigationBar = find.byKey(
      const ValueKey('liquidGlassNavigationBar'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Home')),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester.getTopLeft(indicator).dx,
      lessThan(tester.getTopLeft(navigationBar).dx),
    );

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('frosted quality skips the reflective magnifier', (tester) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        liquidGlassQuality: LiquidGlassQuality.frosted,
      ),
    );

    expect(find.byType(RawMagnifier), findsNothing);
  });

  testWidgets('icon wrappers stay outside the gradient mask', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: FloatingNavigationBar(
            liquidGlass: true,
            liquidGlassQuality: LiquidGlassQuality.reflective,
            destinations: [
              const FloatingNavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              FloatingNavigationDestination(
                icon: const Icon(Icons.bolt_outlined),
                label: 'Dynamic',
                iconWrapper: (icon) => Badge(
                  label: const Text('1'),
                  child: icon,
                ),
              ),
              const FloatingNavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Mine',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(Badge), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ShaderMask),
        matching: find.byType(Badge),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Badge),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
  });
}

class _NavigationHost extends StatefulWidget {
  const _NavigationHost({
    required this.destinations,
    this.initialIndex = 0,
    this.onSelected,
    this.liquidGlassQuality = LiquidGlassQuality.reflective,
  });

  final List<Widget> destinations;
  final int initialIndex;
  final ValueChanged<int>? onSelected;
  final LiquidGlassQuality liquidGlassQuality;

  @override
  State<_NavigationHost> createState() => _NavigationHostState();
}

class _NavigationHostState extends State<_NavigationHost> {
  late int selectedIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: FloatingNavigationBar(
      liquidGlass: true,
      liquidGlassQuality: widget.liquidGlassQuality,
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: widget.destinations,
      onDestinationSelected: (index) {
        setState(() => selectedIndex = index);
        widget.onSelected?.call(index);
      },
    ),
  );
}
