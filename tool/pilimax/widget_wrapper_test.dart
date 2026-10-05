import 'dart:ui' show SemanticsAction, Tristate;

import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:PiliMax/common/widgets/flutter/list_tile.dart' as custom;
import 'package:PiliMax/common/widgets/flutter/text/text.dart' as custom;
import 'package:PiliMax/common/widgets/flutter/vertical_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;

void main() {
  testWidgets('extended ListTile gestures respect child gesture ownership', (
    tester,
  ) async {
    var tileTapUps = 0;
    var childTaps = 0;
    final focusNode = FocusNode();
    final statesController = WidgetStatesController();
    addTearDown(focusNode.dispose);
    addTearDown(statesController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: custom.ListTile(
            title: const Text('tile'),
            trailing: IconButton(
              onPressed: () => childTaps += 1,
              icon: const Icon(Icons.add),
            ),
            onTapUp: (_) => tileTapUps += 1,
            focusNode: focusNode,
            statesController: statesController,
          ),
        ),
      ),
    );

    await tester.tap(find.text('tile'));
    await tester.pump();
    expect(tileTapUps, 1);
    expect(childTaps, 0);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(tileTapUps, 1);
    expect(childTaps, 1);

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(statesController.value, contains(WidgetState.focused));
  });

  testWidgets('compact Text updates its overflow affordance', (tester) async {
    var expanded = false;
    var short = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Center(
                child: SizedBox(
                  width: 40,
                  child: custom.Text(
                    short ? 'a' : 'a long line that cannot fit',
                    style: const TextStyle(fontSize: 20),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    primary: Colors.blue,
                    onShowMore: () => expanded = true,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('查看更多'), findsOneWidget);
    await tester.tap(find.text('查看更多'));
    expect(expanded, isTrue);

    rebuild(() => short = true);
    await tester.pumpAndSettle();
    expect(find.text('查看更多'), findsNothing);
  });

  testWidgets('VerticalSlider increases when dragged upward', (tester) async {
    var value = 0.5;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 60,
                height: 300,
                child: VerticalSlider(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(VerticalSlider), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(value, greaterThan(0.5));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.label, isNull);
    expect(slider.showValueIndicator, ShowValueIndicator.never);
  });

  testWidgets('floating navigation delegates interaction and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selectedIndex = 0;

    try {
      await tester.pumpWidget(
        mui.MaterialApp(
          home: mui.Material(
            child: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.bottomCenter,
                child: FloatingNavigationBar(
                  key: const ValueKey('floating-navigation'),
                  selectedIndex: selectedIndex,
                  backgroundColor: Colors.yellow,
                  elevation: 7,
                  shadowColor: Colors.red,
                  surfaceTintColor: Colors.green,
                  indicatorColor: Colors.blue,
                  indicatorShape: const RoundedRectangleBorder(),
                  labelBehavior:
                      mui.NavigationDestinationLabelBehavior.alwaysShow,
                  labelPadding: const EdgeInsets.only(top: 3),
                  onDestinationSelected: (index) {
                    setState(() => selectedIndex = index);
                  },
                  destinations: const [
                    FloatingNavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    FloatingNavigationDestination(
                      icon: Icon(Icons.search_outlined),
                      selectedIcon: Icon(Icons.search),
                      label: 'Search',
                    ),
                    FloatingNavigationDestination(
                      icon: Icon(Icons.block_outlined),
                      label: 'Disabled',
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navigationFinder = find.byType(mui.NavigationBar);
      expect(navigationFinder, findsOneWidget);
      expect(tester.getSize(navigationFinder).height, 64);
      final navigation = tester.widget<mui.NavigationBar>(navigationFinder);
      expect(navigation.elevation, 7);
      expect(navigation.backgroundColor, Colors.transparent);
      expect(navigation.surfaceTintColor, Colors.green);
      expect(navigation.indicatorColor, Colors.transparent);
      expect(navigation.indicatorShape, const RoundedRectangleBorder());
      expect(navigation.labelPadding, const EdgeInsets.only(top: 3));
      final indicator = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('floatingNavigationIndicator')),
      );
      expect(
        (indicator.decoration as ShapeDecoration).color,
        Colors.blue,
      );
      expect(
        navigation.labelBehavior,
        mui.NavigationDestinationLabelBehavior.alwaysShow,
      );
      final homeSemantics = tester
          .getSemantics(find.text('Home'))
          .getSemanticsData();
      expect(homeSemantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(homeSemantics.hasAction(SemanticsAction.tap), isTrue);

      final shell = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('glassVisualShell')),
      );
      final decoration = shell.decoration as BoxDecoration;
      expect(decoration.color, Colors.yellow);
      expect(decoration.borderRadius, isNotNull);
      expect(decoration.border, isNotNull);
      expect(decoration.boxShadow!.single.color, Colors.red);
      final navigationMaterial = tester.widget<mui.Material>(
        find
            .descendant(
              of: navigationFinder,
              matching: find.byType(mui.Material),
            )
            .first,
      );
      expect(navigationMaterial.elevation, 7);
      expect(navigationMaterial.shadowColor, Colors.transparent);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
      final searchSemantics = tester
          .getSemantics(find.text('Search'))
          .getSemanticsData();
      expect(searchSemantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(searchSemantics.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('floating navigation fits five destinations on a narrow view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      mui.MaterialApp(
        home: Align(
          alignment: Alignment.bottomCenter,
          child: FloatingNavigationBar(
            destinations: const [
              FloatingNavigationDestination(icon: Icon(Icons.home), label: 'A'),
              FloatingNavigationDestination(icon: Icon(Icons.home), label: 'B'),
              FloatingNavigationDestination(icon: Icon(Icons.home), label: 'C'),
              FloatingNavigationDestination(icon: Icon(Icons.home), label: 'D'),
              FloatingNavigationDestination(icon: Icon(Icons.home), label: 'E'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(mui.NavigationBar)).width,
      lessThanOrEqualTo(320),
    );
    final bar = tester.getRect(find.byType(mui.NavigationBar));
    expect(bar.center.dx, 160);
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(320));
    expect(find.text('E'), findsOneWidget);
  });
}
