import 'package:PiliMax/common/widgets/flutter/page/page_view.dart'
    as directional_page;
import 'package:PiliMax/common/widgets/flutter/page/tabs.dart'
    as directional_tabs;
import 'package:PiliMax/common/widgets/flutter/tabs.dart' as custom_tabs;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kind in _ViewKind.values) {
    final target = kind == _ViewKind.directional ? 3 : 2;

    testWidgets('${kind.name} warps across non-adjacent tabs', (
      tester,
    ) async {
      final tracker = _PageTracker();
      final controller = TabController(
        length: 4,
        vsync: const TestVSync(),
        animationDuration: const Duration(milliseconds: 300),
      );
      final children = List<Widget>.generate(
        4,
        (index) => _TrackedPage(index: index, tracker: tracker),
      );
      await _pumpView(
        tester,
        kind,
        controller: controller,
        children: children,
      );

      final initialMarker = tracker.markers[0];
      final forwardMiddleInits = [tracker.inits[1] ?? 0, tracker.inits[2] ?? 0];
      final forwardMiddleBuilds = [
        tracker.builds[1] ?? 0,
        tracker.builds[2] ?? 0,
      ];

      controller.animateTo(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(controller.index, 3);
      expect(_page(tester, kind), greaterThan(2));
      expect(_page(tester, kind), lessThan(3));
      expect(
        [tracker.inits[1] ?? 0, tracker.inits[2] ?? 0],
        forwardMiddleInits,
      );
      expect(
        [tracker.builds[1] ?? 0, tracker.builds[2] ?? 0],
        forwardMiddleBuilds,
      );

      await tester.pumpAndSettle();
      expect(controller.index, 3);
      expect(_page(tester, kind), closeTo(3, 0.001));
      expect(tracker.inits[3], 1);

      final reverseMiddleInits = [tracker.inits[1] ?? 0, tracker.inits[2] ?? 0];
      final reverseMiddleBuilds = [
        tracker.builds[1] ?? 0,
        tracker.builds[2] ?? 0,
      ];
      controller.animateTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(controller.index, 0);
      expect(_page(tester, kind), greaterThan(0));
      expect(_page(tester, kind), lessThan(1));
      expect(
        [tracker.inits[1] ?? 0, tracker.inits[2] ?? 0],
        reverseMiddleInits,
      );
      expect(
        [tracker.builds[1] ?? 0, tracker.builds[2] ?? 0],
        reverseMiddleBuilds,
      );

      await tester.pumpAndSettle();
      expect(controller.index, 0);
      expect(_page(tester, kind), closeTo(0, 0.001));
      expect(tracker.inits[0], 1);
      expect(tracker.markers[0], initialMarker);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('${kind.name} keeps the latest rapid animateTo target', (
      tester,
    ) async {
      final controller = TabController(
        length: 4,
        vsync: const TestVSync(),
        animationDuration: const Duration(milliseconds: 300),
      );
      await _pumpView(tester, kind, controller: controller);

      controller.animateTo(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_page(tester, kind), greaterThan(2));

      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.index, 1);
      expect(_page(tester, kind), greaterThan(1));
      expect(_page(tester, kind), lessThan(2));

      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(_page(tester, kind), closeTo(1, 0.001));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('${kind.name} synchronizes a replaced DefaultTabController', (
      tester,
    ) async {
      final key = GlobalKey<_DefaultControllerHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _DefaultControllerHarness(key: key, kind: kind),
        ),
      );

      final viewContext = tester.element(find.byKey(_viewKey));
      final oldController = DefaultTabController.of(viewContext)
        ..animateTo(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_page(tester, kind), greaterThan(target - 1));
      expect(_page(tester, kind), lessThan(target));

      key.currentState!.replaceController();
      await tester.pump();

      final newController = DefaultTabController.of(
        tester.element(find.byKey(_viewKey)),
      );
      expect(newController, isNot(same(oldController)));
      expect(newController.index, target);
      expect(_page(tester, kind), closeTo(target, 0.001));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('${kind.name} detaches old and disposed controller listeners', (
      tester,
    ) async {
      final first = TabController(length: 4, vsync: const TestVSync());
      final second = TabController(
        length: 4,
        initialIndex: target,
        vsync: const TestVSync(),
      );
      final key = GlobalKey<_ExplicitControllerHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _ExplicitControllerHarness(
            key: key,
            kind: kind,
            first: first,
            second: second,
          ),
        ),
      );

      key.currentState!.useSecondController();
      await tester.pumpAndSettle();
      expect(_page(tester, kind), closeTo(target, 0.001));

      first.index = 1;
      await tester.pumpAndSettle();
      expect(second.index, target);
      expect(_page(tester, kind), closeTo(target, 0.001));

      final disposalTarget = target == 3 ? 0 : 3;
      second.animateTo(
        disposalTarget,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(() => second.index = target, returnsNormally);
      expect(tester.takeException(), isNull);
      first.dispose();
      second.dispose();
    });
  }

  testWidgets('CustomTabBarView reports drag progress through offset', (
    tester,
  ) async {
    final controller = TabController(length: 3, vsync: const TestVSync());
    await _pumpView(tester, _ViewKind.custom, controller: controller);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_viewKey)),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.index, 0);
    expect(controller.offset, greaterThan(0.1));
    expect(controller.offset, lessThan(0.9));
    expect(
      controller.animation!.value,
      closeTo(_page(tester, _ViewKind.custom), 0.001),
    );

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(0, 0.001));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

const _viewKey = ValueKey('tab-view');

enum _ViewKind { directional, custom }

Future<void> _pumpView(
  WidgetTester tester,
  _ViewKind kind, {
  required TabController controller,
  List<Widget>? children,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: _buildView(
            kind,
            controller: controller,
            children: children,
          ),
        ),
      ),
    ),
  );
}

Widget _buildView(
  _ViewKind kind, {
  TabController? controller,
  List<Widget>? children,
}) {
  children ??= List<Widget>.generate(
    controller?.length ?? 4,
    (index) => Center(child: Text('tab-$index')),
  );
  return switch (kind) {
    _ViewKind.directional =>
      directional_tabs.TabBarView<_TestHorizontalDragGestureRecognizer>(
        key: _viewKey,
        controller: controller,
        horizontalDragGestureRecognizer:
            _TestHorizontalDragGestureRecognizer.new,
        children: children,
      ),
    _ViewKind.custom => custom_tabs.CustomTabBarView(
      key: _viewKey,
      controller: controller,
      children: children,
    ),
  };
}

double _page(WidgetTester tester, _ViewKind kind) {
  return switch (kind) {
    _ViewKind.directional =>
      tester
          .widget<
            directional_page.PageView<_TestHorizontalDragGestureRecognizer>
          >(
            find.byWidgetPredicate(
              (widget) =>
                  widget
                      is directional_page.PageView<
                        _TestHorizontalDragGestureRecognizer
                      >,
            ),
          )
          .controller!
          .page!,
    _ViewKind.custom =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!,
  };
}

class _DefaultControllerHarness extends StatefulWidget {
  const _DefaultControllerHarness({super.key, required this.kind});

  final _ViewKind kind;

  @override
  State<_DefaultControllerHarness> createState() =>
      _DefaultControllerHarnessState();
}

class _DefaultControllerHarnessState extends State<_DefaultControllerHarness> {
  Duration _duration = const Duration(seconds: 1);

  void replaceController() {
    setState(() => _duration = const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      animationDuration: _duration,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: _buildView(widget.kind),
        ),
      ),
    );
  }
}

class _ExplicitControllerHarness extends StatefulWidget {
  const _ExplicitControllerHarness({
    super.key,
    required this.kind,
    required this.first,
    required this.second,
  });

  final _ViewKind kind;
  final TabController first;
  final TabController second;

  @override
  State<_ExplicitControllerHarness> createState() =>
      _ExplicitControllerHarnessState();
}

class _ExplicitControllerHarnessState
    extends State<_ExplicitControllerHarness> {
  bool _useSecond = false;

  void useSecondController() {
    setState(() => _useSecond = true);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 400,
        height: 300,
        child: _buildView(
          widget.kind,
          controller: _useSecond ? widget.second : widget.first,
        ),
      ),
    );
  }
}

class _TestHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {}

class _PageTracker {
  int _nextMarker = 0;
  final Map<int, int> inits = {};
  final Map<int, int> builds = {};
  final Map<int, int> markers = {};

  int init(int index) {
    inits.update(index, (count) => count + 1, ifAbsent: () => 1);
    return markers[index] = _nextMarker++;
  }

  void build(int index) {
    builds.update(index, (count) => count + 1, ifAbsent: () => 1);
  }
}

class _TrackedPage extends StatefulWidget {
  const _TrackedPage({required this.index, required this.tracker});

  final int index;
  final _PageTracker tracker;

  @override
  State<_TrackedPage> createState() => _TrackedPageState();
}

class _TrackedPageState extends State<_TrackedPage>
    with AutomaticKeepAliveClientMixin {
  late final int marker = widget.tracker.init(widget.index);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    widget.tracker.build(widget.index);
    return Center(child: Text('tracked-${widget.index}-$marker'));
  }
}
