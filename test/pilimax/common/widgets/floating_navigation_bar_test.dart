import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_capability.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/common/widgets/liquid_glass_filter.dart';
import 'package:PiliMax/pilimax/common/widgets/liquid_glass_quality.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
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
    GlassStyle? glassStyle,
    double bottomPadding = 8.0,
    double bottomLift = 0.0,
  }) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: _NavigationHost(
        initialIndex: selectedIndex,
        onSelected: onSelected,
        destinations: destinations(),
        liquidGlassQuality: liquidGlassQuality,
        glassStyle: glassStyle,
        bottomPadding: bottomPadding,
        bottomLift: bottomLift,
      ),
    );
  }

  testWidgets('liquid glass mode adds a clipped backdrop filter', (
    tester,
  ) async {
    await tester.pumpWidget(host(onSelected: (_) {}));

    // Shader-capable engines have the shell blur plus the shader-backed
    // filter; fallback engines keep only the shell blur.
    expect(find.byType(BackdropFilter), findsWidgets);
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

  testWidgets('mouse drag keeps the lens expanded inside the shell', (
    tester,
  ) async {
    await tester.pumpWidget(host(onSelected: (_) {}));

    final indicator = find.byKey(const ValueKey('liquidGlassIndicator'));
    final idleHeight = tester.getSize(indicator).height;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Home')),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final shellRect = tester.getRect(
      find.byKey(const ValueKey('liquidGlassNavigationBar')),
    );
    final indicatorRect = tester.getRect(indicator);
    expect(indicatorRect.height, greaterThan(idleHeight));
    expect(indicatorRect.top, greaterThanOrEqualTo(shellRect.top));
    expect(indicatorRect.bottom, lessThanOrEqualTo(shellRect.bottom));

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('drag release keeps the lens and shell visually continuous', (
    tester,
  ) async {
    await tester.pumpWidget(host(onSelected: (_) {}));

    final indicator = find.byKey(const ValueKey('liquidGlassIndicator'));
    final shell = find.byKey(const ValueKey('liquidGlassVisualShell'));
    final mineCenter = tester.getCenter(find.text('Mine'));
    final idleShellX = tester.getTopLeft(shell).dx;
    final gesture = await tester.startGesture(mineCenter);
    await gesture.moveBy(const Offset(-48, 0));
    await tester.pump();

    final draggedLensCenter = tester.getCenter(indicator).dx;
    final draggedShellX = tester.getTopLeft(shell).dx;
    expect((draggedShellX - idleShellX).abs(), greaterThan(0.1));

    await gesture.up();
    await tester.pump();

    expect(
      (tester.getCenter(indicator).dx - draggedLensCenter).abs(),
      lessThan(1.5),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('pressed lens remains inside the floating bar', (tester) async {
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
      greaterThanOrEqualTo(tester.getTopLeft(navigationBar).dx),
    );
    expect(
      tester.getBottomRight(indicator).dx,
      lessThanOrEqualTo(tester.getBottomRight(navigationBar).dx),
    );
    expect(
      tester.getTopLeft(indicator).dy,
      greaterThanOrEqualTo(tester.getTopLeft(navigationBar).dy),
    );
    expect(
      tester.getBottomRight(indicator).dy,
      lessThanOrEqualTo(tester.getBottomRight(navigationBar).dy),
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

  testWidgets('soft quality skips both backdrop filters and magnifier', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        liquidGlassQuality: LiquidGlassQuality.soft,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RawMagnifier), findsNothing);
    expect(
      find.byKey(const ValueKey('liquidGlassNavigationBar')),
      findsOneWidget,
    );
  });

  testWidgets('legacy soft quality keeps the legacy visual layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        liquidGlassQuality: LiquidGlassQuality.soft,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RawMagnifier), findsNothing);
    expect(find.byType(ShaderMask), findsWidgets);
  });

  testWidgets('soft glass style keeps the lightweight visual path', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.soft,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RawMagnifier), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(LiquidGlassFilter), findsNothing);
    expect(
      find.byKey(const ValueKey('liquidGlassNavigationBar')),
      findsOneWidget,
    );
  });

  testWidgets(
    'new liquid style follows the centralized fallback when shader is unsupported',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          onSelected: (_) {},
          glassStyle: GlassStyle.liquid,
        ),
      );

      if (!GlassCapability.supportsShaderFilter) {
        final initialMode = GlassCapability.preferredLiquidMode();
        expect(
          find.byType(RawMagnifier),
          initialMode == GlassFallbackMode.reflective
              ? findsOneWidget
              : findsNothing,
        );
        expect(find.byType(BackdropFilter), findsOneWidget);
      }
    },
  );

  testWidgets('explicit liquid style ignores the legacy soft quality', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.liquid,
        liquidGlassQuality: LiquidGlassQuality.soft,
      ),
    );

    // The old quality key must not turn an explicit new liquid selection into
    // the shader-free soft path. A filter may still be the visible fallback
    // while the shader asset is loading.
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('none glass style keeps the ordinary navigation path', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.none,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RawMagnifier), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('liquidGlassVisualShell')), findsNothing);
  });

  testWidgets('bottom lift changes only the floating bar position', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.soft,
        bottomPadding: 8,
        bottomLift: 0,
      ),
    );
    final bar = find.byKey(const ValueKey('liquidGlassNavigationBar'));
    final baseTop = tester.getTopLeft(bar).dy;
    final baseSize = tester.getSize(bar);

    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.soft,
        bottomPadding: 8,
        bottomLift: 24,
      ),
    );
    await tester.pump();

    expect(tester.getTopLeft(bar).dy, closeTo(baseTop - 24, 0.01));
    expect(tester.getSize(bar), baseSize);
  });

  testWidgets('bottom lift does not resize the Scaffold body', (tester) async {
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.soft,
        bottomLift: 0,
      ),
    );
    final body = find.byKey(const ValueKey('navigationBody'));
    final baseBodySize = tester.getSize(body);

    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        glassStyle: GlassStyle.soft,
        bottomLift: 24,
      ),
    );
    await tester.pump();

    expect(tester.getSize(body), baseBodySize);
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

  testWidgets('icon wrapper semantics remain available in glass mode', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: FloatingNavigationBar(
            glassStyle: GlassStyle.soft,
            destinations: [
              const FloatingNavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              FloatingNavigationDestination(
                icon: const Icon(Icons.bolt_outlined),
                label: 'Dynamic',
                iconWrapper: (icon) => Semantics(
                  label: 'Dynamic unread 1',
                  child: icon,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final dynamicTab = find.bySemanticsLabel(
      RegExp(r'Dynamic(?:.*Dynamic unread 1|.*unread 1)'),
    );
    expect(dynamicTab, findsOneWidget);
    semantics.dispose();
  });
}

class _NavigationHost extends StatefulWidget {
  const _NavigationHost({
    required this.destinations,
    this.initialIndex = 0,
    this.onSelected,
    this.liquidGlassQuality = LiquidGlassQuality.reflective,
    this.glassStyle,
    this.bottomPadding = 8.0,
    this.bottomLift = 0.0,
  });

  final List<Widget> destinations;
  final int initialIndex;
  final ValueChanged<int>? onSelected;
  final LiquidGlassQuality liquidGlassQuality;
  final GlassStyle? glassStyle;
  final double bottomPadding;
  final double bottomLift;

  @override
  State<_NavigationHost> createState() => _NavigationHostState();
}

class _NavigationHostState extends State<_NavigationHost> {
  late int selectedIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: const SizedBox.expand(key: ValueKey('navigationBody')),
    bottomNavigationBar: FloatingNavigationBar(
      liquidGlass: true,
      glassStyle: widget.glassStyle,
      liquidGlassQuality: widget.liquidGlassQuality,
      bottomPadding: widget.bottomPadding,
      bottomLift: widget.bottomLift,
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
