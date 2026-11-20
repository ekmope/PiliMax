import 'dart:ui' show ImageFilter, Tristate;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const destinations = [
    FloatingNavigationDestination(
      icon: Icon(Icons.home_outlined),
      label: 'Home',
    ),
    FloatingNavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      label: 'Dynamic',
    ),
  ];

  Widget host({
    GlassStyle? style = GlassStyle.soft,
    List<Widget>? items,
    int selectedIndex = 0,
    ValueChanged<int>? onSelected,
    Brightness brightness = Brightness.light,
    NavigationDestinationLabelBehavior? labelBehavior,
    double bottomLift = 0,
    EdgeInsets safePadding = EdgeInsets.zero,
    Widget Function(Widget bar)? wrapBar,
    TextDirection textDirection = TextDirection.ltr,
    bool disableAnimations = false,
  }) {
    final bar = FloatingNavigationBar(
      glassStyle: style,
      selectedIndex: selectedIndex,
      destinations: items ?? destinations,
      onDestinationSelected: onSelected,
      labelBehavior: labelBehavior,
      bottomLift: bottomLift,
    );
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: safePadding,
          viewPadding: safePadding,
          disableAnimations: disableAnimations,
        ),
        child: Directionality(textDirection: textDirection, child: child!),
      ),
      home: Scaffold(
        body: const RepaintBoundary(
          child: SizedBox.expand(key: ValueKey('content')),
        ),
        bottomNavigationBar: wrapBar?.call(bar) ?? bar,
      ),
    );
  }

  void setViewport(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  double labelOpacity(WidgetTester tester, String label) {
    final fade = find.ancestor(
      of: find.text(label),
      matching: find.byType(FadeTransition),
    );
    return tester.widget<FadeTransition>(fade.first).opacity.value;
  }

  const dockShellKey = ValueKey('glassVisualShell');
  const indicatorKey = ValueKey('floatingNavigationIndicator');
  const glassLensKey = ValueKey('liquidGlassLens');
  const lensContentKey = ValueKey('liquidGlassLensContent');
  const warpKey = ValueKey('liquidGlassLensWarp');

  Offset dockDestination(WidgetTester tester, int index, {int count = 2}) {
    final shell = tester.getRect(find.byKey(dockShellKey));
    return Offset(
      shell.left + 4 + (shell.width - 8) / count * (index + 0.5),
      shell.center.dy,
    );
  }

  testWidgets('renders regular and soft glass styles with only soft blur', (
    tester,
  ) async {
    await tester.pumpWidget(host(style: GlassStyle.none));
    expect(find.byKey(const ValueKey('glassNavigationBar')), findsOneWidget);
    expect(find.byKey(const ValueKey('glassVisualShell')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(host(style: GlassStyle.soft));
    expect(find.byKey(const ValueKey('glassNavigationBar')), findsOneWidget);
    expect(find.byKey(const ValueKey('glassVisualShell')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('softGlassBackdropFilter')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);

    final nav = tester.widget<NavigationBar>(
      find.byKey(const ValueKey('floatingNavigationSemanticsBar')),
    );
    expect(
      nav.overlayColor?.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    expect(nav.overlayColor?.resolve({WidgetState.hovered})?.a, greaterThan(0));
    final focus = nav.overlayColor?.resolve({WidgetState.focused});
    expect(focus?.a, greaterThan(0));
    expect(
      nav.overlayColor?.resolve({WidgetState.pressed, WidgetState.focused}),
      focus,
    );
    expect(nav.indicatorColor, Colors.transparent);
  });

  for (final count in [3, 4, 5]) {
    for (final (width, padding) in [
      (390.0, EdgeInsets.zero),
      (390.0, const EdgeInsets.fromLTRB(24, 0, 8, 24)),
      (600.0, EdgeInsets.zero),
    ]) {
      testWidgets(
        'centers $count destinations within $width px and $padding',
        (tester) async {
          setViewport(tester, width);
          await tester.pumpWidget(
            host(
              safePadding: padding,
              items: List.generate(
                count,
                (index) => FloatingNavigationDestination(
                  icon: const Icon(Icons.circle_outlined),
                  label: 'Tab $index',
                ),
              ),
            ),
          );
          final bar = tester.getRect(
            find.byKey(const ValueKey('glassVisualShell')),
          );
          final availableWidth = width - padding.horizontal;
          expect(
            bar.center.dx,
            moreOrLessEquals(padding.left + availableWidth / 2),
          );
          expect(bar.left, greaterThanOrEqualTo(padding.left));
          expect(bar.right, lessThanOrEqualTo(width - padding.right));
          expect(bar.width / count, greaterThanOrEqualTo(48));
          expect(bar.height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'keeps the indicator aligned with compressed narrow destinations',
    (
      tester,
    ) async {
      setViewport(tester, 390);
      final items = List.generate(
        5,
        (index) => FloatingNavigationDestination(
          icon: Icon(
            key: ValueKey('narrow-icon-$index'),
            Icons.circle_outlined,
          ),
          label: 'Tab $index',
        ),
      );
      await tester.pumpWidget(host(items: items, selectedIndex: 4));
      await tester.pumpAndSettle();
      final indicator = tester.getRect(
        find.byKey(const ValueKey('floatingNavigationIndicator')),
      );
      final icon = tester.getRect(find.byKey(const ValueKey('narrow-icon-4')));
      expect(indicator.center.dx, moreOrLessEquals(icon.center.dx));
      expect(indicator.right, lessThanOrEqualTo(390));
    },
  );

  for (final count in [3, 4, 5]) {
    testWidgets(
      'keeps $count destination icons and tap targets inside the safe shell',
      (tester) async {
        setViewport(tester, 390);
        final items = List.generate(
          count,
          (index) => FloatingNavigationDestination(
            icon: Icon(
              Icons.circle_outlined,
              key: ValueKey('safeAreaIcon-$index'),
            ),
            label: 'Tab $index',
          ),
        );
        await tester.pumpWidget(host(items: items));
        await tester.pumpAndSettle();
        final originalShell = tester.getRect(
          find.byKey(const ValueKey('glassVisualShell')),
        );
        final originalIcons = List.generate(
          count,
          (index) => tester.getRect(
            find.byKey(ValueKey('safeAreaIcon-$index')),
          ),
        );

        final selected = <int>[];
        await tester.pumpWidget(
          host(
            items: items,
            safePadding: const EdgeInsets.fromLTRB(24, 0, 8, 24),
            onSelected: selected.add,
          ),
        );
        await tester.pumpAndSettle();
        final shell = tester.getRect(
          find.byKey(const ValueKey('glassVisualShell')),
        );
        expect(shell.height, 64);
        for (var index = 0; index < count; index++) {
          final icon = tester.getRect(
            find.byKey(ValueKey('safeAreaIcon-$index')),
          );
          final contentWidth = shell.width - 2 * 4.0;
          final expectedCenterX =
              shell.left + 4.0 + contentWidth * (index + 0.5) / count;
          expect(icon.center.dx, moreOrLessEquals(expectedCenterX));
          expect(
            icon.center.dy - shell.top,
            moreOrLessEquals(
              originalIcons[index].center.dy - originalShell.top,
            ),
          );
          expect(
            icon.width,
            moreOrLessEquals(originalIcons[index].width),
          );
          expect(
            icon.height,
            moreOrLessEquals(originalIcons[index].height),
          );
          final destination = tester.getRect(
            find.byType(NavigationDestination).at(index),
          );
          expect(destination.height, greaterThanOrEqualTo(48));
          expect(destination.width, greaterThanOrEqualTo(48));
          await tester.tapAt(Offset(expectedCenterX, shell.center.dy));
        }
        expect(selected, List.generate(count, (index) => index));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('supports light and dark themes with each label mode', (
    tester,
  ) async {
    final colors = <Brightness, Color>{};
    for (final brightness in Brightness.values) {
      for (final mode in NavigationDestinationLabelBehavior.values) {
        await tester.pumpWidget(
          host(brightness: brightness, labelBehavior: mode),
        );
        await tester.pumpAndSettle();
        final tint = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('softGlassSurfaceTint')),
        );
        final color = tint.color;
        colors[brightness] = color;
        expect(color.a, inExclusiveRange(0, 1));
        expect(
          labelOpacity(tester, 'Home'),
          mode == NavigationDestinationLabelBehavior.alwaysHide ? 0 : 1,
        );
        expect(
          labelOpacity(tester, 'Dynamic'),
          mode == NavigationDestinationLabelBehavior.alwaysShow ? 1 : 0,
        );
        expect(tester.takeException(), isNull);
      }
    }
    expect(
      colors[Brightness.dark]!.computeLuminance(),
      lessThan(colors[Brightness.light]!.computeLuminance()),
    );
  });

  testWidgets(
    'reports selection and repeated taps on the current destination',
    (
      tester,
    ) async {
      final selected = <int>[];
      await tester.pumpWidget(host(onSelected: selected.add));
      await tester.tap(find.text('Home'));
      await tester.tap(find.text('Dynamic'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(selectedIndex: 1, onSelected: selected.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dynamic'));
      expect(selected, [0, 1, 1]);
    },
  );

  testWidgets('keeps a completed tap when a competing recognizer wins', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      host(
        onSelected: selected.add,
        wrapBar: (bar) => RawGestureDetector(
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (recognizer) {},
                ),
          },
          child: bar,
        ),
      ),
    );
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );

    await tester.tapAt(
      Offset(shell.left + shell.width * 0.75, shell.center.dy),
    );
    await tester.pumpAndSettle();

    expect(selected, [1]);
    final indicator = tester.getRect(
      find.byKey(const ValueKey('floatingNavigationIndicator')),
    );
    expect(indicator.center.dx, greaterThan(shell.center.dx));
  });

  testWidgets('press feedback expands the indicator before release', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final indicator = find.byKey(
      const ValueKey('floatingNavigationIndicator'),
    );
    final idleWidth = tester.getSize(indicator).width;
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    final gesture = await tester.startGesture(
      Offset(shell.left + shell.width / 4, shell.center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(indicator).width, greaterThan(idleWidth));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator).width, moreOrLessEquals(idleWidth));
  });

  testWidgets('liquid press overflows symmetrically around the dock shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: FloatingNavigationBar(
            glassStyle: GlassStyle.liquid,
            destinations: destinations,
          ),
        ),
      ),
    );
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    final indicatorFinder = find.byKey(
      const ValueKey('floatingNavigationIndicator'),
    );
    final idleIndicator = tester.getRect(indicatorFinder);
    expect(idleIndicator.top, greaterThanOrEqualTo(shell.top));
    expect(idleIndicator.bottom, lessThanOrEqualTo(shell.bottom));

    final gesture = await tester.startGesture(shell.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));

    final indicator = tester.getRect(indicatorFinder);
    final topOverflow = shell.top - indicator.top;
    final bottomOverflow = indicator.bottom - shell.bottom;
    expect(topOverflow, greaterThan(0));
    expect(indicator.bottom, greaterThan(shell.bottom));
    expect(topOverflow, closeTo(bottomOverflow, 0.01));

    await gesture.up();
    await tester.pumpAndSettle();
    final releasedIndicator = tester.getRect(indicatorFinder);
    expect(releasedIndicator.top, greaterThanOrEqualTo(shell.top));
    expect(releasedIndicator.bottom, lessThanOrEqualTo(shell.bottom));
  });

  testWidgets('keeps idle edge gaps and expands to the rim while pressed', (
    tester,
  ) async {
    setViewport(tester, 390);
    final indicator = find.byKey(
      const ValueKey('floatingNavigationIndicator'),
    );

    await tester.pumpWidget(host(selectedIndex: 0));
    await tester.pumpAndSettle();
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    final idleFirst = tester.getRect(indicator);
    expect(idleFirst.left, greaterThan(shell.left));

    final gesture = await tester.startGesture(
      Offset(shell.left + shell.width / 4, shell.center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.getRect(indicator).left, lessThanOrEqualTo(shell.left));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(selectedIndex: 1));
    await tester.pumpAndSettle();
    final idleLast = tester.getRect(indicator);
    expect(idleLast.right, lessThan(shell.right));

    final lastGesture = await tester.startGesture(
      Offset(shell.left + shell.width * 0.75, shell.center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.getRect(indicator).right, greaterThanOrEqualTo(shell.right));
    await lastGesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('horizontal drag previews and selects on release', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(host(onSelected: selected.add));
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    final indicator = find.byKey(
      const ValueKey('floatingNavigationIndicator'),
    );
    final idleCenter = tester.getCenter(indicator);
    final gesture = await tester.startGesture(
      Offset(shell.left + shell.width / 4, shell.center.dy),
    );
    await gesture.moveBy(Offset(shell.width / 2, 0));
    await tester.pump();
    expect(tester.getCenter(indicator).dx, greaterThan(idleCenter.dx));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [1]);
  });

  for (final style in GlassStyle.values) {
    testWidgets('${style.name}: vertical cancellation survives later moves', (
      tester,
    ) async {
      final selected = <int>[];
      await tester.pumpWidget(host(style: style, onSelected: selected.add));
      final expected = tester.getCenter(find.byKey(indicatorKey));

      for (final steerHorizontally in [false, true]) {
        final gesture = await tester.startGesture(dockDestination(tester, 1));
        await gesture.moveBy(const Offset(2, -42));
        if (steerHorizontally) await gesture.moveBy(const Offset(-80, 30));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected, isEmpty);
        expect(tester.getCenter(find.byKey(indicatorKey)), expected);
      }
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('only the fast drag projects forward in ${direction.name}', (
      tester,
    ) async {
      final selected = <int>[];
      await tester.pumpWidget(
        host(textDirection: direction, onSelected: selected.add),
      );
      final first = direction == TextDirection.ltr ? 0 : 1;
      final start = dockDestination(tester, first);
      final pitch = (tester.getSize(find.byKey(dockShellKey)).width - 8) / 2;
      final dragDistance = Offset(
        pitch * 0.35 * (direction == TextDirection.ltr ? 1 : -1),
        0,
      );
      await tester.timedDragFrom(
        start,
        dragDistance,
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      await tester.timedDragFrom(
        start,
        dragDistance,
        const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
      expect(selected, [1]);
    });
  }

  testWidgets('ignores secondary mouse clicks and keeps keyboard activation', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      host(style: GlassStyle.liquid, onSelected: selected.add),
    );
    await tester.tapAt(
      dockDestination(tester, 1),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(find.byKey(lensContentKey), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, [1]);
  });

  testWidgets('pointer cancellation restores the committed destination', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(host(onSelected: selected.add));
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    final indicator = find.byKey(
      const ValueKey('floatingNavigationIndicator'),
    );
    final gesture = await tester.startGesture(
      Offset(shell.left + shell.width / 4, shell.center.dy),
    );
    await gesture.moveBy(Offset(shell.width / 2, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(
      tester.getCenter(indicator).dx,
      moreOrLessEquals(shell.left + shell.width / 4),
    );
  });

  testWidgets('horizontal drag skips disabled destinations', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      host(
        onSelected: selected.add,
        items: const [
          FloatingNavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          FloatingNavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            label: 'Disabled',
            enabled: false,
          ),
          FloatingNavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
    final shell = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    final gesture = await tester.startGesture(
      Offset(shell.left + shell.width / 6, shell.center.dy),
    );
    await gesture.moveBy(Offset(shell.width * 2 / 3, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);
  });

  testWidgets('does not activate disabled destinations', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final selected = <int>[];
      await tester.pumpWidget(
        host(
          onSelected: selected.add,
          items: const [
            FloatingNavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            FloatingNavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              label: 'Dynamic',
              enabled: false,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Dynamic'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      final data = tester
          .getSemantics(find.bySemanticsLabel(RegExp('Dynamic')))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'keeps wrapped badges and destination semantics after selection',
    (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final items = [
          destinations.first,
          FloatingNavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt),
            label: 'Dynamic',
            iconWrapper: (icon) => Semantics(
              label: '4 unread messages',
              child: Badge(label: const Text('4'), child: icon),
            ),
          ),
        ];
        for (final index in [0, 1]) {
          await tester.pumpWidget(host(items: items, selectedIndex: index));
          await tester.pumpAndSettle();
          expect(find.text('4'), findsOneWidget);
          expect(
            find.byIcon(index == 1 ? Icons.bolt : Icons.bolt_outlined),
            findsOneWidget,
          );
          final data = tester
              .getSemantics(find.bySemanticsLabel(RegExp('Dynamic')))
              .getSemanticsData();
          expect(data.label, contains('4 unread messages'));
          expect(
            data.flagsCollection.isSelected,
            index == 1 ? Tristate.isTrue : Tristate.isFalse,
          );
          expect(data.hasAction(SemanticsAction.tap), isTrue);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('the shell and selected pill are both glass at rest', (
    tester,
  ) async {
    await tester.pumpWidget(host(style: GlassStyle.liquid));
    expect(tester.widget(find.byKey(dockShellKey)), isA<LiquidGlass>());
    final lens = tester.widget<LiquidGlass>(find.byKey(glassLensKey));
    expect(lens.style.refraction, lessThan(0));
    expect(lens.style.rim, greaterThan(0));
    final plate = tester.widget<DecoratedBox>(find.byKey(indicatorKey));
    expect((plate.decoration as ShapeDecoration).color!.a, lessThan(0.2));
    expect(find.byType(LiquidGlass), findsNWidgets(2));
    expect(find.byKey(lensContentKey), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('softGlassBackdropFilter')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lens content refraction requires lift and shader support', (
    tester,
  ) async {
    await tester.pumpWidget(host(style: GlassStyle.liquid));
    final lens = find.byKey(glassLensKey);
    final restingElement = tester.element(lens);
    final restingStyle = tester.widget<LiquidGlass>(lens).style;
    final gesture = await tester.startGesture(dockDestination(tester, 0));
    await tester.pumpAndSettle();
    expect(tester.element(lens), same(restingElement));
    expect(tester.widget<LiquidGlass>(lens).style, restingStyle);
    expect(find.byKey(lensContentKey), findsOneWidget);
    expect(find.byType(NavigationBar), findsNWidgets(2));
    final warp = ImageFilter.isShaderFilterSupported;
    expect(find.byKey(warpKey), warp ? findsOneWidget : findsNothing);
    if (warp) {
      final clip = tester.widget<ClipPath>(
        find
            .ancestor(
              of: find.byKey(warpKey),
              matching: find.byType(ClipPath),
            )
            .first,
      );
      expect(clip.clipBehavior, Clip.antiAliasWithSaveLayer);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.element(lens), same(restingElement));
    expect(find.byType(LiquidGlass), findsNWidgets(2));
    expect(find.byKey(lensContentKey), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('liquid tap commits during lift and releases after its peak', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      host(style: GlassStyle.liquid, onSelected: selected.add),
    );
    final indicator = find.byKey(indicatorKey);
    final restingHeight = tester.getSize(indicator).height;
    final gesture = await tester.startGesture(dockDestination(tester, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final heightBeforeRelease = tester.getSize(indicator).height;
    await gesture.up();
    expect(selected, [1]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(indicator).height, greaterThan(heightBeforeRelease));
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator).height, restingHeight);
    expect(find.byKey(glassLensKey), findsOneWidget);
    expect(find.byKey(lensContentKey), findsNothing);
    expect(selected, [1]);
  });

  testWidgets('dragging the liquid lens does not repaint the page body', (
    tester,
  ) async {
    await tester.pumpWidget(host(style: GlassStyle.liquid));
    final page = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('content')),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final gesture = await tester.startGesture(dockDestination(tester, 0));
    await tester.pumpAndSettle();
    page.debugResetMetrics();
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(14, 0));
    await tester.pump();
    expect(page.debugSymmetricPaintCount + page.debugAsymmetricPaintCount, 0);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion uses immediate selection without a raised lens', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      host(
        style: GlassStyle.liquid,
        disableAnimations: true,
        onSelected: selected.add,
      ),
    );
    final target = dockDestination(tester, 1);
    final gesture = await tester.startGesture(target);
    await tester.pump();
    expect(tester.getCenter(find.byKey(indicatorKey)), target);
    expect(find.byKey(glassLensKey), findsOneWidget);
    expect(find.byKey(lensContentKey), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(selected, [1]);
    expect(find.byKey(glassLensKey), findsOneWidget);
    expect(find.byKey(lensContentKey), findsNothing);
  });

  testWidgets('liquid glass keeps the bottom-lift transform', (tester) async {
    await tester.pumpWidget(host(style: GlassStyle.liquid));
    final resting = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );

    await tester.pumpWidget(
      host(style: GlassStyle.liquid, bottomLift: 24),
    );
    final lifted = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );

    expect(lifted.size, resting.size);
    expect(lifted.top, moreOrLessEquals(resting.top - 24));
  });

  testWidgets('bottom lift moves the bar without resizing the page body', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final body = tester.getRect(find.byKey(const ValueKey('content')));
    final bar = tester.getRect(find.byKey(const ValueKey('glassVisualShell')));
    await tester.pumpWidget(host(bottomLift: 24));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('content'))), body);
    final lifted = tester.getRect(
      find.byKey(const ValueKey('glassVisualShell')),
    );
    expect(lifted.size, bar.size);
    expect(lifted.center.dx, bar.center.dx);
    expect(lifted.top, moreOrLessEquals(bar.top - 24));
  });

  testWidgets('hide and restore wrapper keeps the bottom slot content-sized', (
    tester,
  ) async {
    setViewport(tester, 390);
    const safePadding = EdgeInsets.fromLTRB(24, 0, 8, 24);
    const bottomLift = 24.0;
    await tester.pumpWidget(
      host(safePadding: safePadding, bottomLift: bottomLift),
    );
    final body = tester.getRect(find.byKey(const ValueKey('content')));
    final bar = tester.getRect(find.byKey(const ValueKey('glassVisualShell')));
    final screen = tester.getRect(find.byType(Scaffold));

    for (final progress in [0.0, 1.0, 0.0]) {
      await tester.pumpWidget(
        host(
          safePadding: safePadding,
          bottomLift: bottomLift,
          wrapBar: (bar) => Stack(
            key: const ValueKey('bottomSlot'),
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(0, bottomLift * progress),
                child: FractionalTranslation(
                  translation: Offset(0, progress),
                  child: bar,
                ),
              ),
              if (progress == 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: safePadding.bottom + 2,
                  height: 8,
                  child: GestureDetector(
                    key: const ValueKey('restoreStrip'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('content'))), body);
      final slot = tester.getRect(find.byKey(const ValueKey('bottomSlot')));
      expect(slot.top, body.bottom);
      expect(slot.bottom, screen.bottom);
      final currentBar = tester.getRect(
        find.byKey(const ValueKey('glassVisualShell')),
      );
      expect(currentBar.center.dx, bar.center.dx);
      expect(currentBar.size, bar.size);
      if (progress == 0) {
        expect(currentBar, bar);
        expect(currentBar.bottom, lessThan(screen.bottom));
        expect(find.byKey(const ValueKey('restoreStrip')), findsNothing);
      } else {
        expect(currentBar.top, greaterThanOrEqualTo(screen.bottom));
        final strip = tester.getRect(
          find.byKey(const ValueKey('restoreStrip')),
        );
        expect(strip.bottom, lessThanOrEqualTo(screen.bottom));
        expect(strip.center.dx, screen.center.dx);
      }
      expect(tester.takeException(), isNull);
    }
  });
}
