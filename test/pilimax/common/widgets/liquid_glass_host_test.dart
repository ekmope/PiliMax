import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _paneRect = Rect.fromLTWH(100, 100, 80, 48);
const _clearStyle = LiquidGlassStyle(tint: Colors.transparent, blur: 0);

Widget _scene(List<Widget> layers, {bool enabled = true}) {
  return MaterialApp(
    home: LiquidGlassHost(
      enabled: enabled,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: ColoredBox(color: Colors.red)),
          ...layers,
        ],
      ),
    ),
  );
}

Widget _pane(Rect rect, {Rect? hold, LiquidGlassStyle style = _clearStyle}) {
  return Positioned.fromRect(
    rect: rect,
    child: LiquidGlass(style: style, hold: hold),
  );
}

LiquidGlassCapture get _capture => LiquidGlassHost.debugLastCapture!;

void main() {
  setUp(() => LiquidGlassHost.debugLastCapture = null);

  testWidgets('nested hosts share one capture of the full glass material', (
    tester,
  ) async {
    const hazy = LiquidGlassStyle(
      tint: Colors.transparent,
      blur: 0,
      haze: 0.7,
      hazeBlur: 24,
    );
    final before = LiquidGlassHost.debugCaptures;
    await tester.pumpWidget(
      _scene([
        LiquidGlassHost(
          enabled: true,
          child: Stack(children: [_pane(_paneRect, style: hazy)]),
        ),
      ]),
    );
    expect(LiquidGlassHost.debugCaptures - before, 1);
    expect(_capture.snapshots, 1);
    final pane = _capture.panes.single;
    expect(pane.pane, _paneRect);
    // The clear pass stays at device resolution even when the haze is strong.
    expect(pane.scale, tester.view.devicePixelRatio);
  });

  testWidgets('a still-mounted offstage pane releases its capture', (
    tester,
  ) async {
    final before = LiquidGlassHost.debugHeldCaptures;
    Widget scene({required bool offstage, bool enabled = true}) => _scene([
      _pane(_paneRect),
      Offstage(
        offstage: offstage,
        child: Stack(children: [_pane(_paneRect.translate(0, 100))]),
      ),
    ], enabled: enabled);

    await tester.pumpWidget(scene(offstage: false));
    expect(LiquidGlassHost.debugHeldCaptures, before + 2);

    await tester.pumpWidget(scene(offstage: true));
    expect(_capture.panes, hasLength(1));
    expect(LiquidGlassHost.debugHeldCaptures, before + 1);

    await tester.pumpWidget(scene(offstage: false));
    expect(LiquidGlassHost.debugHeldCaptures, before + 2);
    await tester.pumpWidget(scene(offstage: false, enabled: false));
    expect(LiquidGlassHost.debugHeldCaptures, before);
  });

  testWidgets('a moving pane reuses its frost and haze within the hold', (
    tester,
  ) async {
    const hold = Rect.fromLTWH(70, 80, 260, 130);
    const style = LiquidGlassStyle(
      tint: Colors.transparent,
      haze: 0.7,
      hazeBlur: 12,
    );
    Widget scene(Rect rect) => _scene([
      _pane(rect, hold: hold.shift(-rect.topLeft), style: style),
    ]);

    await tester.pumpWidget(scene(_paneRect));
    final first = _capture.panes.single;
    expect(_capture.snapshots, 1);

    await tester.pumpWidget(scene(_paneRect.translate(60, 0)));
    expect(_capture.snapshots, 0);
    expect(_capture.panes.single.atlas, same(first.atlas));

    await tester.pumpWidget(scene(_paneRect.translate(400, 0)));
    expect(_capture.snapshots, 1);
  });

  testWidgets('a glass fade updates semantics when it becomes visible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final animation = AnimationController(vsync: tester);
    addTearDown(animation.dispose);
    await tester.pumpWidget(
      _scene([
        LiquidGlassFade(
          opacity: animation,
          child: Center(
            child: Semantics(
              label: 'Glass content',
              child: const SizedBox.square(dimension: 40),
            ),
          ),
        ),
      ]),
    );
    final content = find.bySemanticsLabel('Glass content');
    expect(content, findsNothing);

    animation.value = 1;
    await tester.pump();
    expect(content, findsOneWidget);

    animation.value = 0;
    await tester.pump();
    expect(content, findsNothing);
  });
}
