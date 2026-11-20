import 'package:PiliMax/pages/setting/widgets/liquid_glass_switch.dart';
import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget switchApp({
    required ValueChanged<bool>? onChanged,
    bool disableAnimations = false,
    TextDirection direction = TextDirection.ltr,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          ),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: LiquidGlassSwitch(
                value: false,
                onChanged: onChanged,
                semanticLabel: 'Navbar显示文字',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lift uses a glass pane within a 48 dp switch target', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(switchApp(onChanged: changes.add));
    final control = find.byType(LiquidGlassSwitch);
    final glass = find.byType(LiquidGlass);
    expect(tester.getSize(control).height, 48);
    expect(glass, findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(control));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 140));
    expect(glass, findsOneWidget);

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(glass, findsNothing);
    expect(changes, isEmpty);
  });

  testWidgets('reduced motion omits lift while keeping the tap action', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      switchApp(onChanged: changes.add, disableAnimations: true),
    );
    final control = find.byType(LiquidGlassSwitch);
    final gesture = await tester.startGesture(tester.getCenter(control));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(LiquidGlass), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(changes, [true]);
  });

  testWidgets('an unaccepted RTL drag returns to the controlled value', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      switchApp(onChanged: changes.add, direction: TextDirection.rtl),
    );
    final control = find.byType(LiquidGlassSwitch);
    final thumb = find
        .descendant(of: control, matching: find.byType(DecoratedBox))
        .last;
    final restPosition = tester.getCenter(thumb);
    final gesture = await tester.startGesture(tester.getCenter(control));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(tester.getCenter(thumb).dx, lessThan(restPosition.dx));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changes, [true]);
    expect(tester.getCenter(thumb), restPosition);
    expect(find.byType(LiquidGlass), findsNothing);
  });
}
