import 'dart:ui' show Tristate;

import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:flutter/semantics.dart';
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
        ),
        child: child!,
      ),
      home: Scaffold(
        body: const SizedBox.expand(key: ValueKey('content')),
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
    for (final state in [
      {WidgetState.pressed},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed, WidgetState.focused},
    ]) {
      expect(nav.overlayColor?.resolve(state), Colors.transparent);
    }
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
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(indicator).width, greaterThan(idleWidth));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator).width, moreOrLessEquals(idleWidth));
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
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.getRect(indicator).left, lessThanOrEqualTo(shell.left));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(selectedIndex: 2));
    await tester.pumpAndSettle();
    final idleLast = tester.getRect(indicator);
    expect(idleLast.right, lessThan(shell.right));

    final lastGesture = await tester.startGesture(
      Offset(shell.left + shell.width * 0.75, shell.center.dy),
    );
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

  testWidgets('vertical drag cancels without selecting a destination', (
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
    await gesture.moveBy(const Offset(2, -64));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(tester.getCenter(indicator).dx, moreOrLessEquals(idleCenter.dx));
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
