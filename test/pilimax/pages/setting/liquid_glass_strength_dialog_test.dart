import 'package:PiliMax/pages/setting/widgets/liquid_glass_strength_dialog.dart';
import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'previews percentage and quality and returns them on confirmation',
    (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final changes = <(int, LiquidGlassQuality)>[];
      ({int strength, LiquidGlassQuality quality})? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result =
                      await showDialog<
                        ({int strength, LiquidGlassQuality quality})
                      >(
                        context: context,
                        builder: (_) => LiquidGlassStrengthDialog(
                          initialValue: 70,
                          initialQuality: LiquidGlassQuality.standard,
                          onChanged: (strength, quality) =>
                              changes.add((strength, quality)),
                        ),
                      );
                },
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      );

      final open = find.text('打开设置');
      final dock = find.byType(FloatingNavigationBar);
      final sliderFinder = find.byType(Slider);
      final ultra = find.widgetWithText(ChoiceChip, '超清');
      Slider slider() => tester.widget<Slider>(sliderFinder);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(slider().min, 0);
      expect(slider().max, 100);
      expect(slider().divisions, 100);
      expect(slider().value, 70);
      expect(find.text('70%'), findsOneWidget);
      expect(dock, findsOneWidget);

      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(tester.widget<FloatingNavigationBar>(dock).selectedIndex, 0);
      slider().onChanged!(37.4);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FloatingNavigationBar>(dock).liquidGlassStrength,
        0.37,
      );
      expect(find.text('37%'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(slider().value, 70);
      slider().onChanged!(0);
      await tester.pump();
      expect(tester.widget<FloatingNavigationBar>(dock).liquidGlassStrength, 0);
      slider().onChanged!(100);
      await tester.pump();
      expect(tester.widget<FloatingNavigationBar>(dock).liquidGlassStrength, 1);
      await tester.ensureVisible(ultra);
      await tester.tap(ultra);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(ultra).selected, isTrue);
      expect(
        LiquidGlassScope.qualityOf(tester.element(dock)),
        LiquidGlassQuality.ultra,
      );
      expect(changes, [
        (37, LiquidGlassQuality.standard),
        (0, LiquidGlassQuality.standard),
        (100, LiquidGlassQuality.standard),
        (100, LiquidGlassQuality.ultra),
      ]);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, (
        strength: 100,
        quality: LiquidGlassQuality.ultra,
      ));
      expect(tester.takeException(), isNull);
    },
  );
}
