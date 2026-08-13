import 'package:PiliMax/pilimax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pilimax/pages/video/video_page_transitions_builder.dart';
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
}
