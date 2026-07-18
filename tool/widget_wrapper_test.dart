import 'dart:ui' show SemanticsAction, Tristate;

import 'package:PiliMax/common/widgets/floating_navigation_bar.dart';
import 'package:PiliMax/common/widgets/flutter/list_tile.dart' as custom;
import 'package:PiliMax/common/widgets/flutter/text/text.dart' as custom;
import 'package:PiliMax/common/widgets/flutter/vertical_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.bottomCenter,
              child: FloatingNavigationBar(
                key: const ValueKey('floating-navigation'),
                selectedIndex: selectedIndex,
                elevation: 7,
                shadowColor: Colors.red,
                indicatorShape: const RoundedRectangleBorder(),
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

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.getSize(find.byType(NavigationBar)).height, 56);
    final homeSemantics = tester
        .getSemantics(find.text('Home'))
        .getSemanticsData();
    expect(homeSemantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(homeSemantics.hasAction(SemanticsAction.tap), isTrue);

    final outerMaterial = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byKey(const ValueKey('floating-navigation')),
            matching: find.byType(Material),
          ),
        )
        .singleWhere((material) => material.shape is RoundedSuperellipseBorder);
    expect(outerMaterial.elevation, 7);
    expect(outerMaterial.shadowColor, Colors.red);

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
    semantics.dispose();
  });

  testWidgets('floating navigation fits five destinations on a narrow view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
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
      tester.getSize(find.byType(NavigationBar)).width,
      lessThanOrEqualTo(320),
    );
    expect(find.text('E'), findsOneWidget);
  });
}
