import 'package:PiliMax/common/widgets/flutter/draggable_scrollable_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dynamic sheet does not shrink after a scrolled list reaches the top',
    (tester) async {
      const sheetKey = ValueKey('dynamic-sheet');
      late ScrollController listController;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: DynDraggableScrollableSheet(
                initialChildSize: 0.8,
                minChildSize: 0.2,
                maxChildSize: 1,
                expand: false,
                builder: (context, controller) {
                  listController = controller;
                  return SizedBox(
                    key: sheetKey,
                    child: ListView.builder(
                      controller: controller,
                      itemExtent: 40,
                      itemCount: 100,
                      itemBuilder: (_, index) => Text('item-$index'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      listController.jumpTo(200);
      await tester.pump();

      final initialHeight = tester.getSize(find.byKey(sheetKey)).height;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(sheetKey)),
      );
      await gesture.moveBy(const Offset(0, 220));
      await tester.pump();
      expect(listController.offset, 0);
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(tester.getSize(find.byKey(sheetKey)).height, initialHeight);
      await gesture.up();
      await tester.pump();

      final nextGesture = await tester.startGesture(
        tester.getCenter(find.byKey(sheetKey)),
      );
      await nextGesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(sheetKey)).height,
        lessThan(initialHeight),
      );
      await nextGesture.up();
    },
  );

  testWidgets('topic sheet restores offset after the list attaches later', (
    tester,
  ) async {
    var showList = false;
    late StateSetter rebuild;
    ScrollController? listController;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SizedBox(
              height: 500,
              child: TopicDraggableScrollableSheet(
                initialChildSize: 1,
                minChildSize: 1,
                maxChildSize: 1,
                initialScrollOffset: 120,
                builder: (context, controller) {
                  if (!showList) return const SizedBox();
                  listController = controller;
                  return ListView.builder(
                    controller: controller,
                    itemExtent: 40,
                    itemCount: 100,
                    itemBuilder: (_, index) => Text('item-$index'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    expect(listController, isNull);

    rebuild(() => showList = true);
    await tester.pump();
    expect(listController, isNotNull);
    expect(listController!.offset, 120);
  });

  testWidgets(
    'topic sheet restores offset after initially empty content grows',
    (
      tester,
    ) async {
      var itemCount = 0;
      late StateSetter rebuild;
      late ScrollController listController;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                height: 500,
                child: TopicDraggableScrollableSheet(
                  initialChildSize: 1,
                  minChildSize: 1,
                  maxChildSize: 1,
                  initialScrollOffset: 120,
                  builder: (context, controller) {
                    listController = controller;
                    return ListView.builder(
                      controller: controller,
                      itemExtent: 40,
                      itemCount: itemCount,
                      itemBuilder: (_, index) => Text('item-$index'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(listController.offset, 120);

      rebuild(() => itemCount = 100);
      await tester.pump();
      expect(listController.offset, 120);
    },
  );
}
