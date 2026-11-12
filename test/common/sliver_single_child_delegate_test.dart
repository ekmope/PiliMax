import 'package:PiliMax/common/skeleton/video_card_h.dart';
import 'package:PiliMax/common/skeleton/video_reply.dart';
import 'package:PiliMax/common/sliver_single_child_delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('bounds children and rebuilds when count or child changes', (
    tester,
  ) async {
    const delegate = SliverSingleChildDelegate(
      count: 3,
      child: SizedBox(height: 40),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomScrollView(slivers: [SliverList(delegate: delegate)]),
      ),
    );
    final context = tester.element(find.byType(CustomScrollView));
    expect(delegate.build(context, -1), isNull);
    expect(delegate.build(context, 2), isNotNull);
    expect(delegate.build(context, 3), isNull);
    expect(
      const SliverSingleChildDelegate(
        count: 4,
        child: SizedBox(height: 40),
      ).shouldRebuild(delegate),
      isTrue,
    );
    expect(
      const SliverSingleChildDelegate(
        count: 3,
        child: SizedBox(height: 60),
      ).shouldRebuild(delegate),
      isTrue,
    );
    expect(delegate.shouldRebuild(delegate), isFalse);

    await tester.pumpWidget(
      const MaterialApp(
        home: CustomScrollView(
          slivers: [
            SliverList(
              delegate: SliverSingleChildDelegate(
                count: 0,
                child: SizedBox(height: 40),
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 40),
      findsNothing,
    );
  });

  for (final kind in ['list', 'grid', 'prototype']) {
    testWidgets('$kind skeleton survives ticker and reduced-motion changes', (
      tester,
    ) async {
      final controls = ValueNotifier((ticker: true, reduced: false));
      final scroll = ScrollController();
      await tester.pumpWidget(
        _SkeletonPage(kind: kind, controls: controls, controller: scroll),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      for (final state in [
        (ticker: false, reduced: false),
        (ticker: true, reduced: false),
        (ticker: true, reduced: true),
        (ticker: true, reduced: false),
      ]) {
        controls.value = state;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controls.dispose();
      scroll.dispose();
    });
  }

  testWidgets('covered skeleton page can rebuild then return without damage', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final controls = ValueNotifier((ticker: true, reduced: false));
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: _SkeletonBody(
          kind: 'prototype',
          controls: controls,
          controller: scroll,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    navigator.currentState!.push<void>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const Scaffold(body: Text('detail')),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    await tester.pump();
    await tester.pump();
    controls.value = (ticker: true, reduced: true);
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    controls.value = (ticker: true, reduced: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('detail'), findsNothing);
    expect(find.byType(VideoReplySkeleton), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    controls.dispose();
    scroll.dispose();
  });
}

class _SkeletonPage extends StatelessWidget {
  const _SkeletonPage({
    required this.kind,
    required this.controls,
    required this.controller,
  });
  final String kind;
  final ValueNotifier<({bool ticker, bool reduced})> controls;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: _SkeletonBody(
      kind: kind,
      controls: controls,
      controller: controller,
    ),
  );
}

class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody({
    required this.kind,
    required this.controls,
    required this.controller,
  });
  final String kind;
  final ValueNotifier<({bool ticker, bool reduced})> controls;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ValueListenableBuilder(
      valueListenable: controls,
      builder: (context, state, _) {
        final SliverChildDelegate delegate = SliverSingleChildDelegate(
          count: 15,
          child: kind == 'grid'
              ? const VideoCardHSkeleton()
              : const VideoReplySkeleton(),
        );
        final sliver = switch (kind) {
          'grid' => SliverGrid(
            delegate: delegate,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 110,
            ),
          ),
          'prototype' => SliverPrototypeExtentList(
            delegate: delegate,
            prototypeItem: const VideoReplySkeleton(),
          ),
          _ => SliverList(delegate: delegate),
        };
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: state.reduced,
          ),
          child: TickerMode(
            enabled: state.ticker,
            child: CustomScrollView(controller: controller, slivers: [sliver]),
          ),
        );
      },
    ),
  );
}
