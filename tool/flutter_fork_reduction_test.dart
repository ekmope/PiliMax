import 'dart:ui' show SemanticsAction;

import 'package:PiliMax/common/widgets/flutter/chat_list_view.dart';
import 'package:PiliMax/common/widgets/flutter/draggable_scrollable_sheet.dart';
import 'package:PiliMax/common/widgets/flutter/page/page_view.dart'
    as custom_page;
import 'package:PiliMax/common/widgets/flutter/page/tabs.dart' as custom_tabs;
import 'package:PiliMax/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliMax/common/widgets/flutter/text_field/text_field.dart';
import 'package:PiliMax/common/widgets/flutter/vertical_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'custom PageView keeps drag, controller, and semantics behavior',
    (
      tester,
    ) async {
      final controller = PageController();
      final changed = <int>[];
      const pageViewKey = ValueKey('page-view');
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: custom_page.PageView<_TestHorizontalDragGestureRecognizer>(
              key: pageViewKey,
              controller: controller,
              onPageChanged: changed.add,
              horizontalDragGestureRecognizer:
                  _TestHorizontalDragGestureRecognizer.new,
              children: const [Text('page-0'), Text('page-1'), Text('page-2')],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('page-0'), findsOneWidget);
      expect(
        find.semantics.scrollable(),
        isSemantics(
          hasScrollLeftAction: true,
          hasScrollRightAction: false,
        ),
      );
      tester.semantics.scrollLeft();
      await tester.pumpAndSettle();
      expect(find.text('page-1'), findsOneWidget);
      expect(controller.page, 1);

      final animation = controller.animateToPage(
        2,
        duration: const Duration(milliseconds: 50),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();
      await animation;
      expect(find.text('page-2'), findsOneWidget);
      expect(controller.page, 2);

      await tester.drag(find.byKey(pageViewKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('page-1'), findsOneWidget);
      expect(controller.page, 1);
      expect(changed, containsAllInOrder([1, 2, 1]));

      semantics.dispose();
      controller.dispose();
    },
  );

  testWidgets('custom TabBarView follows direct, animated, and drag changes', (
    tester,
  ) async {
    final key = GlobalKey<_TabHarnessState>();
    await tester.pumpWidget(MaterialApp(home: _TabHarness(key: key)));

    expect(find.text('tab-0'), findsOneWidget);
    key.currentState!.controller.index = 2;
    await tester.pumpAndSettle();
    expect(find.text('tab-2'), findsOneWidget);

    key.currentState!.controller.animateTo(
      1,
      duration: const Duration(milliseconds: 40),
    );
    await tester.pumpAndSettle();
    expect(find.text('tab-1'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('tab-view')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.index, 2);
    expect(find.text('tab-2'), findsOneWidget);
  });

  testWidgets('custom PageView respects disabled user scrolling', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: custom_page.PageView<_TestHorizontalDragGestureRecognizer>(
            physics: const PageScrollPhysics().applyTo(
              const NeverScrollableScrollPhysics(),
            ),
            horizontalDragGestureRecognizer:
                _TestHorizontalDragGestureRecognizer.new,
            children: const [Text('locked-0'), Text('locked-1')],
          ),
        ),
      ),
    );

    await tester.drag(find.text('locked-0'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('locked-0'), findsOneWidget);
    expect(find.text('locked-1'), findsNothing);
    expect(
      find.semantics.byAction(SemanticsAction.scrollLeft).tryEvaluate(),
      isFalse,
    );
    expect(
      find.semantics.byAction(SemanticsAction.scrollRight).tryEvaluate(),
      isFalse,
    );
    semantics.dispose();
  });

  for (final textDirection in TextDirection.values) {
    for (final reverse in [false, true]) {
      testWidgets(
        'custom PageView semantics follow $textDirection reverse=$reverse',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final controller = PageController();
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: textDirection,
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child:
                      custom_page.PageView<
                        _TestHorizontalDragGestureRecognizer
                      >(
                        controller: controller,
                        reverse: reverse,
                        horizontalDragGestureRecognizer:
                            _TestHorizontalDragGestureRecognizer.new,
                        children: const [Text('first'), Text('second')],
                      ),
                ),
              ),
            ),
          );
          await tester.pump();

          final forwardIsLeft = (textDirection == TextDirection.ltr) != reverse;
          expect(
            find.semantics.scrollable(),
            isSemantics(
              hasScrollLeftAction: forwardIsLeft,
              hasScrollRightAction: !forwardIsLeft,
            ),
          );
          if (forwardIsLeft) {
            tester.semantics.scrollLeft();
          } else {
            tester.semantics.scrollRight();
          }
          await tester.pumpAndSettle();
          expect(controller.page, 1);
          expect(
            find.semantics.scrollable(),
            isSemantics(
              hasScrollLeftAction: !forwardIsLeft,
              hasScrollRightAction: forwardIsLeft,
            ),
          );

          semantics.dispose();
          controller.dispose();
        },
      );
    }
  }

  testWidgets('RichTextField reconciles replacement and IME composition', (
    tester,
  ) async {
    final controller = RichTextEditingController(
      items: [
        RichTextItem(text: 'A', range: const TextRange(start: 0, end: 1)),
        RichTextItem(
          type: RichTextType.at,
          text: '@Bob ',
          rawText: '42',
          range: const TextRange(start: 1, end: 6),
        ),
        RichTextItem(text: 'Z', range: const TextRange(start: 6, end: 7)),
      ],
    );
    const fieldKey = ValueKey('rich-field');
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RichTextField(key: fieldKey, controller: controller),
        ),
      ),
    );

    await tester.tap(find.byKey(fieldKey));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'AXZ',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.plainText, 'AXZ');
    expect(controller.items.every((item) => !item.isRich), isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 2));

    controller.clear();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();
    expect(controller.plainText, '你');
    expect(controller.text, '你');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));

    controller.dispose();
  });

  test(
    'rich selections remain outside atomic nodes and copy raw emoji text',
    () {
      final controller = RichTextEditingController(
        items: [
          RichTextItem(text: 'A', range: const TextRange(start: 0, end: 1)),
          RichTextItem(
            type: RichTextType.emoji,
            text: '[doge]',
            rawText: '[doge]',
            range: const TextRange(start: 1, end: 7),
          ),
        ],
      );

      expect(
        controller.normalizeSelection(const TextSelection.collapsed(offset: 2)),
        const TextSelection.collapsed(offset: 1),
      );
      expect(
        controller.getSelectionText(
          const TextSelection(baseOffset: 1, extentOffset: 7),
        ),
        '[doge]',
      );
      controller.dispose();
    },
  );

  testWidgets('topic sheet restores its nested list offset', (tester) async {
    ScrollController? nestedController;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 500,
          child: TopicDraggableScrollableSheet(
            initialChildSize: 1,
            minChildSize: 1,
            maxChildSize: 1,
            initialScrollOffset: 120,
            builder: (context, controller) {
              nestedController = controller;
              return ListView.builder(
                controller: controller,
                itemExtent: 40,
                itemCount: 100,
                itemBuilder: (_, index) => Text('item-$index'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(nestedController, isNotNull);
    expect(nestedController!.offset, 120);
  });

  testWidgets('short reversed chat lists stay anchored to the bottom', (
    tester,
  ) async {
    const listKey = ValueKey('chat-list');
    const itemKey = ValueKey('chat-item');
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          height: 300,
          child: ChatListView.separated(
            key: listKey,
            itemCount: 1,
            itemBuilder: _chatItemBuilder,
            separatorBuilder: _separatorBuilder,
          ),
        ),
      ),
    );

    final listBottom = tester.getBottomLeft(find.byKey(listKey)).dy;
    final itemBottom = tester.getBottomLeft(find.byKey(itemKey)).dy;
    expect(itemBottom, closeTo(listBottom, 0.1));
  });

  testWidgets('vertical tabs expose selected semantics', (tester) async {
    final key = GlobalKey<_VerticalTabsHarnessState>();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: _VerticalTabsHarness(key: key)));

    expect(
      tester.getSemantics(find.text('One')),
      matchesSemantics(
        label: 'One',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.index, 1);
    expect(
      tester.getSemantics(find.text('Two')),
      matchesSemantics(
        label: 'Two',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}

Widget _chatItemBuilder(BuildContext context, int index) =>
    const SizedBox(key: ValueKey('chat-item'), height: 50, child: Text('chat'));

Widget _separatorBuilder(BuildContext context, int index) =>
    const SizedBox(height: 8);

class _TabHarness extends StatefulWidget {
  const _TabHarness({super.key});

  @override
  State<_TabHarness> createState() => _TabHarnessState();
}

class _TabHarnessState extends State<_TabHarness>
    with SingleTickerProviderStateMixin {
  late final TabController controller = TabController(length: 3, vsync: this);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 400,
    height: 300,
    child: custom_tabs.TabBarView<_TestHorizontalDragGestureRecognizer>(
      key: const ValueKey('tab-view'),
      controller: controller,
      horizontalDragGestureRecognizer: _TestHorizontalDragGestureRecognizer.new,
      children: const [Text('tab-0'), Text('tab-1'), Text('tab-2')],
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _VerticalTabsHarness extends StatefulWidget {
  const _VerticalTabsHarness({super.key});

  @override
  State<_VerticalTabsHarness> createState() => _VerticalTabsHarnessState();
}

class _VerticalTabsHarnessState extends State<_VerticalTabsHarness>
    with SingleTickerProviderStateMixin {
  late final TabController controller = TabController(length: 2, vsync: this);

  @override
  Widget build(BuildContext context) => Material(
    child: SizedBox(
      width: 100,
      height: 160,
      child: VerticalTabBar(
        controller: controller,
        tabs: const [
          VerticalTab(text: 'One'),
          VerticalTab(text: 'Two'),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _TestHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {}
