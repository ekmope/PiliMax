import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_page_transitions_builder.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'keeps a live responsive-reflow exit unscaled when media cannot split out',
    (tester) async {
      const target = VideoReturnTarget(
        rect: Rect.fromLTWH(16, 96, 368, 160),
        visibleRect: Rect.fromLTWH(16, 96, 368, 160),
        borderRadius: BorderRadius.all(Radius.circular(8)),
        layout: VideoTransitionSourceLayout.horizontalRow,
        isResponsiveReflow: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: VideoPageExitTransition(
                progress: 0.5,
                returnTarget: target,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final transformFinder = find.descendant(
        of: find.byType(VideoPageExitTransition),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
      final matrix = tester.widget<Transform>(transformFinder).transform;
      expect(matrix.storage[0], 1);
      expect(matrix.storage[5], 1);
      expect(matrix.storage[12], 0);
      expect(matrix.storage[13], 0);
    },
  );

  testWidgets(
    'contains a live detail page instead of cropping it to an unlike card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const target = VideoReturnTarget(
        rect: Rect.fromLTWH(0, 100, 360, 450),
        visibleRect: Rect.fromLTWH(0, 100, 360, 450),
        borderRadius: BorderRadius.all(Radius.circular(8)),
        layout: VideoTransitionSourceLayout.horizontalRow,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                height: 800,
                child: VideoPageExitTransition(
                  progress: 1,
                  returnTarget: target,
                  child: ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      );

      final transformFinder = find.descendant(
        of: find.byType(VideoPageExitTransition),
        matching: find.byType(Transform),
      );
      final matrix = tester.widget<Transform>(transformFinder).transform;
      expect(matrix.storage[0], closeTo(0.5625, 0.0001));
      expect(matrix.storage[5], closeTo(0.5625, 0.0001));
      expect(matrix.storage[12], closeTo(78.75, 0.0001));
      expect(matrix.storage[13], closeTo(100, 0.0001));
    },
  );

  testWidgets(
    'keeps a vertical-card return contained and covers its letterbox gap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const target = VideoReturnTarget(
        rect: Rect.fromLTWH(20, 140, 320, 180),
        visibleRect: Rect.fromLTWH(20, 140, 320, 180),
        borderRadius: BorderRadius.all(Radius.circular(8)),
        layout: VideoTransitionSourceLayout.verticalCard,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoPageExitTransition(
              progress: 0.5,
              returnTarget: target,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      final transition = find.byType(VideoPageExitTransition);
      final transform = tester.widget<Transform>(
        find.descendant(of: transition, matching: find.byType(Transform)),
      );
      expect(transform.transform.storage[0], closeTo(0.6125, 0.0001));
      expect(transform.transform.storage[5], closeTo(0.6125, 0.0001));
      expect(transform.transform.storage[12], closeTo(69.75, 0.0001));
      expect(transform.transform.storage[13], closeTo(70, 0.0001));
      expect(
        find.descendant(of: transition, matching: find.byType(ClipRRect)),
        findsNothing,
      );
      final expectedSurfaceColor = Pref.darkVideoPage
          ? ThemeUtils.darkTheme.colorScheme.surface
          : Theme.of(tester.element(transition)).colorScheme.surface;
      final containedSurface = find.descendant(
        of: transition,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == expectedSurfaceColor,
        ),
      );
      expect(containedSurface, findsOneWidget);
      final surfacePosition = tester.widget<Positioned>(
        find.ancestor(
          of: containedSurface,
          matching: find.byType(Positioned),
        ),
      );
      expect(surfacePosition.left, 10);
      expect(surfacePosition.top, 70);
      expect(surfacePosition.width, 340);
      expect(surfacePosition.height, 490);
      expect(
        find.ancestor(
          of: containedSurface,
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'waits until handoff before clipping a partially visible source card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const target = VideoReturnTarget(
        rect: Rect.fromLTWH(20, 140, 320, 180),
        visibleRect: Rect.fromLTWH(40, 170, 280, 120),
        borderRadius: BorderRadius.all(Radius.circular(8)),
        layout: VideoTransitionSourceLayout.verticalCard,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoPageExitTransition(
              progress: 0.5,
              returnTarget: target,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      final clip = tester.widget<ClipRect>(
        find.descendant(
          of: find.byType(VideoPageExitTransition),
          matching: find.byType(ClipRect),
        ),
      );
      expect(
        clip.clipper!.getClip(const Size(360, 800)),
        const Rect.fromLTWH(10, 70, 340, 490),
      );
    },
  );
}
