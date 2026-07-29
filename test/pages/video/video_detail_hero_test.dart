import 'dart:io';

import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero_curve.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_ugc_title_height_cache.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/models/common/list_order.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart';
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/models_new/video/video_detail/section.dart';
import 'package:PiliMax/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliMax/pages/video/video_detail_back_progress.dart';
import 'package:PiliMax/pages/video/video_detail_entry_overlay.dart';
import 'package:PiliMax/pages/video/video_detail_fullscreen_exit_settle.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  late Box<dynamic> settingBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'pilimax-video-detail-hero-test-',
    );
    Hive.init(hiveDirectory.path);
    settingBox = await Hive.openBox<dynamic>('setting');
    GStorage.setting = settingBox;
  });

  tearDownAll(() async {
    await settingBox.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  group('VideoDetailHero flight timeline', () {
    test('inverts easeOutCubic for push and pop', () {
      for (var index = 0; index <= 100; index++) {
        final rawProgress = index / 100;
        final pushProgress = videoDetailHeroForwardCurve.transform(rawProgress);
        final popProgress =
            1 - videoDetailHeroForwardCurve.transform(1 - rawProgress);

        expect(
          videoDetailRawProgressForEasedFlight(
            pushProgress,
            isPop: false,
          ),
          closeTo(rawProgress, 0.00005),
          reason: 'push sample $index',
        );
        expect(
          videoDetailRawProgressForEasedFlight(
            popProgress,
            isPop: true,
          ),
          closeTo(rawProgress, 0.00005),
          reason: 'pop sample $index',
        );
      }
    });

    test('keeps the Flutter easeOutCubic shape', () {
      for (var index = 0; index <= 100; index++) {
        final progress = index / 100;
        expect(
          videoDetailHeroForwardCurve.transform(progress),
          closeTo(Curves.easeOutCubic.transform(progress), 0.005),
          reason: 'curve sample $index',
        );
      }
    });

    test('clamps eased progress to the route timeline', () {
      expect(
        videoDetailRawProgressForEasedFlight(-1, isPop: false),
        0,
      );
      expect(
        videoDetailRawProgressForEasedFlight(2, isPop: false),
        1,
      );
      expect(
        videoDetailRawProgressForEasedFlight(-1, isPop: true),
        0,
      );
      expect(
        videoDetailRawProgressForEasedFlight(2, isPop: true),
        1,
      );
    });
  });

  group('VideoDetailHero static media', () {
    testWidgets('clips the resting child only when requested', (tester) async {
      const mediaKey = ValueKey('static-media');

      Future<void> pumpSource({required bool clipStaticChild}) =>
          tester.pumpWidget(
            MaterialApp(
              home: VideoDetailTransitionSource(
                tag: 'static-clip-test',
                child: VideoDetailHero.source(
                  clipStaticChild: clipStaticChild,
                  borderRadius: const BorderRadius.all(Radius.circular(7)),
                  flightChild: const SizedBox(width: 16, height: 9),
                  child: const SizedBox(
                    key: mediaKey,
                    width: 160,
                    height: 90,
                  ),
                ),
              ),
            ),
          );

      await pumpSource(clipStaticChild: true);
      final clippedAncestor = find.ancestor(
        of: find.byKey(mediaKey),
        matching: find.byType(ClipRRect),
      );
      expect(clippedAncestor, findsOneWidget);
      expect(
        tester.widget<ClipRRect>(clippedAncestor).borderRadius,
        const BorderRadius.all(Radius.circular(7)),
      );

      await pumpSource(clipStaticChild: false);
      expect(
        find.ancestor(
          of: find.byKey(mediaKey),
          matching: find.byType(ClipRRect),
        ),
        findsNothing,
      );
    });
  });

  group('VideoTransitionRegistry return recovery', () {
    testWidgets(
      'recovers a recreated source with the same tag, route, and layout',
      (tester) async {
        const tag = 'return-recovery-same-layout';
        final harnessKey = GlobalKey<_TransitionRegistryHarnessState>();
        await tester.pumpWidget(
          MaterialApp(
            home: _TransitionRegistryHarness(key: harnessKey, tag: tag),
          ),
        );

        final token = VideoTransitionRegistry.claim(
          tag: tag,
          contentKey: 'video-1',
        );
        expect(token, isNotNull);

        harnessKey.currentState!.recreateSource(
          borderRadius: const BorderRadius.all(Radius.circular(19)),
        );
        await tester.pump();

        final target = VideoTransitionRegistry.resolveReturn(token!);
        expect(target, isNotNull);
        expect(target!.layout, VideoTransitionSourceLayout.verticalCard);
        expect(
          target.borderRadius,
          const BorderRadius.all(Radius.circular(19)),
        );
        expect(target.rect, token.launchRect);

        token.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('does not recover a source registered before the launch', (
      tester,
    ) async {
      const tag = 'return-recovery-older-source';
      late StateSetter setHarnessState;
      var showLaunchSource = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHarnessState = setState;
              return Scaffold(
                body: Stack(
                  children: [
                    const Positioned(
                      left: 32,
                      top: 80,
                      width: 240,
                      height: 160,
                      child: VideoDetailTransitionSource(
                        tag: tag,
                        child: ColoredBox(color: Colors.grey),
                      ),
                    ),
                    if (showLaunchSource)
                      const Positioned(
                        left: 320,
                        top: 80,
                        width: 240,
                        height: 160,
                        child: VideoDetailTransitionSource(
                          tag: tag,
                          child: VideoDetailHero.source(
                            flightChild: ColoredBox(color: Colors.black),
                            child: ColoredBox(color: Colors.blue),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      final token = VideoTransitionRegistry.claim(
        tag: tag,
        contentKey: 'video-older-source',
      );
      expect(token, isNotNull);
      expect(token!.launchRect.left, 320);

      setHarnessState(() => showLaunchSource = false);
      await tester.pump();

      expect(VideoTransitionRegistry.resolveReturn(token), isNull);

      token.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('returns to a recreated source with a responsive layout', (
      tester,
    ) async {
      const tag = 'return-recovery-different-layout';
      final harnessKey = GlobalKey<_TransitionRegistryHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _TransitionRegistryHarness(key: harnessKey, tag: tag),
        ),
      );

      final token = VideoTransitionRegistry.claim(
        tag: tag,
        contentKey: 'video-2',
      );
      expect(token, isNotNull);

      harnessKey.currentState!.recreateSource(
        layout: VideoTransitionSourceLayout.horizontalRow,
      );
      await tester.pump();

      final target = VideoTransitionRegistry.resolveReturn(token!);
      expect(target, isNotNull);
      expect(target!.isResponsiveReflow, isTrue);
      expect(target.hasMediaTarget, isTrue);

      token.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('returns to a source resized by responsive reflow', (
      tester,
    ) async {
      const tag = 'return-recovery-responsive-size';
      final harnessKey = GlobalKey<_TransitionRegistryHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _TransitionRegistryHarness(key: harnessKey, tag: tag),
        ),
      );

      final token = VideoTransitionRegistry.claim(
        tag: tag,
        contentKey: 'video-responsive-size',
      );
      expect(token, isNotNull);

      harnessKey.currentState!.recreateSource(width: 160, height: 240);
      await tester.pump();

      final target = VideoTransitionRegistry.resolveReturn(token!);
      expect(target, isNotNull);
      expect(target!.isResponsiveReflow, isTrue);
      expect(target.hasMediaTarget, isTrue);

      token.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('rejects responsive reflow with only a clipped media strip', (
      tester,
    ) async {
      const tag = 'return-recovery-clipped-media';
      final harnessKey = GlobalKey<_TransitionRegistryHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _TransitionRegistryHarness(key: harnessKey, tag: tag),
        ),
      );

      final token = VideoTransitionRegistry.claim(
        tag: tag,
        contentKey: 'video-clipped-media',
      );
      expect(token, isNotNull);

      harnessKey.currentState!.recreateSource(
        layout: VideoTransitionSourceLayout.horizontalRow,
        mediaClipHeight: 1,
      );
      await tester.pump();

      expect(VideoTransitionRegistry.resolveReturn(token!), isNull);

      token.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('rejects a recreated source that is no longer visible', (
      tester,
    ) async {
      const tag = 'return-recovery-invisible';
      final harnessKey = GlobalKey<_TransitionRegistryHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _TransitionRegistryHarness(key: harnessKey, tag: tag),
        ),
      );

      final token = VideoTransitionRegistry.claim(
        tag: tag,
        contentKey: 'video-3',
      );
      expect(token, isNotNull);

      harnessKey.currentState!.recreateSource(opacity: 0);
      await tester.pump();

      expect(VideoTransitionRegistry.resolveReturn(token!), isNull);

      token.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  test(
    'fullscreen exit settle waits for delayed target layout metrics',
    () {
      final tracker = VideoDetailFullScreenExitSettleTracker();

      expect(
        tracker.observe(layoutSignature: 1, targetLayoutReady: false),
        isFalse,
      );
      expect(
        tracker.observe(layoutSignature: 1, targetLayoutReady: false),
        isFalse,
      );

      tracker.reset();
      expect(
        tracker.observe(layoutSignature: 2, targetLayoutReady: true),
        isFalse,
      );
      expect(
        tracker.observe(layoutSignature: 3, targetLayoutReady: true),
        isFalse,
      );
      expect(
        tracker.observe(layoutSignature: 3, targetLayoutReady: true),
        isTrue,
      );
    },
  );

  testWidgets(
    'UGC entry overlay keeps a title skeleton without an independent title',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      const detailTitle = 'Detail transition title';
      BuildContext? hostContext;
      VideoDetailEntryOverlayController? controller;
      addTearDown(() {
        controller?.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );

      final backProgress = VideoDetailBackProgressController();
      controller =
          VideoDetailEntryOverlayController(
              overlay: Overlay.of(hostContext!),
              transitionToken: VideoTransitionToken(
                tag: 'title-skeleton-overlay',
                sourceGeneration: -1,
                sourceRoute: null,
                launchRect: const Rect.fromLTWH(24, 80, 240, 160),
                sourceVisibleRect: const Rect.fromLTWH(24, 80, 240, 160),
                mediaLaunchRect: const Rect.fromLTWH(24, 80, 240, 135),
                mediaLaunchBorderRadius: const BorderRadius.all(
                  Radius.circular(10),
                ),
                launchBorderRadius: const BorderRadius.all(Radius.circular(10)),
                sourceLayout: VideoTransitionSourceLayout.verticalCard,
                sourceSurfaceColor: Colors.white,
                title: const VideoTransitionTitleSnapshot(
                  rect: Rect.fromLTWH(32, 220, 224, 20),
                  text: 'Source transition title',
                  textSpan: null,
                  style: TextStyle(fontSize: 14),
                  maxLines: 1,
                  textAlign: TextAlign.start,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  textScaler: TextScaler.noScaling,
                ),
                contentKey: 'video-title',
              ),
              backProgress: backProgress,
              isVertical: false,
              variant: VideoDetailSkeletonVariant.ugc,
              title: detailTitle,
            )
            ..insert()
            ..bindRouteAnimation(const AlwaysStoppedAnimation<double>(1));
      await tester.pump();

      final shellFinder = find.byType(VideoDetailHeroShell);
      expect(shellFinder, findsOneWidget);
      final shell = tester.widget<VideoDetailHeroShell>(shellFinder);
      expect(shell.showUgcTitlePlaceholder, isTrue);
      expect(shell.title, detailTitle);
      expect(find.text(detailTitle), findsNothing);
      expect(find.text('Source transition title'), findsNothing);
      final titleSemantics = find.bySemanticsLabel(detailTitle);
      expect(titleSemantics, findsOneWidget);
      expect(tester.getRect(titleSemantics).height, lessThan(100));

      final reveal = controller.beginReveal();
      await tester.pump();
      expect(find.bySemanticsLabel(detailTitle), findsNothing);
      await tester.pumpAndSettle();
      await reveal;

      controller.dispose();
      controller = null;
      await tester.pump();
      semanticsHandle.dispose();
    },
  );

  group('VideoDetailUgcTitleHeightCache', () {
    test('prioritizes overrides and reuses matching text metrics', () {
      final cache = VideoDetailUgcTitleHeightCache();
      const style = TextStyle(fontSize: 16);

      double resolve({
        String? title = 'A sufficiently long video title for layout',
        double width = 320,
        TextStyle textStyle = style,
        TextScaler textScaler = TextScaler.noScaling,
        TextDirection direction = TextDirection.ltr,
        double? override,
      }) => cache.resolve(
        title: title,
        viewportWidth: width,
        style: textStyle,
        textScaler: textScaler,
        textDirection: direction,
        override: override,
      );

      expect(resolve(title: null, override: 72), 72);
      expect(cache.debugLayoutCount, 0);
      expect(resolve(title: ''), VideoDetailUgcTitleHeightCache.fallbackHeight);
      expect(cache.debugLayoutCount, 0);

      final firstHeight = resolve();
      expect(firstHeight, greaterThan(0));
      expect(cache.debugLayoutCount, 1);
      expect(resolve(), firstHeight);
      expect(cache.debugLayoutCount, 1);
      expect(resolve(override: 64), 64);
      expect(cache.debugLayoutCount, 1);

      resolve(direction: TextDirection.rtl);
      expect(cache.debugLayoutCount, 2);
      resolve(direction: TextDirection.rtl, width: 300);
      expect(cache.debugLayoutCount, 3);
      resolve(
        direction: TextDirection.rtl,
        width: 300,
        textStyle: const TextStyle(fontSize: 18),
      );
      expect(cache.debugLayoutCount, 4);
      resolve(
        direction: TextDirection.rtl,
        width: 300,
        textStyle: const TextStyle(fontSize: 18),
        textScaler: const TextScaler.linear(1.2),
      );
      expect(cache.debugLayoutCount, 5);
    });
  });

  group('Video detail shared UGC layout', () {
    test('uses a split player slot for landscape entry skeletons', () {
      const viewport = Size(1200, 720);

      final portrait = VideoDetailLayoutMetrics.entryPlayerRect(
        viewport,
        isVertical: false,
        topInset: 0,
      );
      final landscape = VideoDetailLayoutMetrics.entryPlayerRect(
        viewport,
        isVertical: false,
        topInset: 0,
        isPortrait: false,
      );

      expect(portrait, const Rect.fromLTWH(0, 0, 1200, 405));
      expect(landscape.left, 0);
      expect(landscape.width, 780);
      expect(landscape.height, 438.75);
      expect(landscape.right, lessThan(viewport.width));
    });

    test('resolves the title and season surface geometry', () {
      const viewport = Size(400, 800);
      final titleRect = VideoDetailLayoutMetrics.ugcTitleRect(
        viewport,
        bodyTop: 270,
        titleHeight: 38,
      );

      expect(
        titleRect,
        const Rect.fromLTWH(
          VideoDetailLayoutMetrics.horizontalPadding,
          323,
          376,
          38,
        ),
      );

      final seasonRect = VideoDetailLayoutMetrics.seasonPanelSurfaceRect(
        const Rect.fromLTWH(12, 500, 376, 48),
      );
      expect(seasonRect, const Rect.fromLTWH(14, 508, 372, 40));
    });

    test('uses the same renderable season selection as the real panel', () {
      final firstSectionEpisodes = <EpisodeItem>[
        EpisodeItem(cid: 11),
        EpisodeItem(cid: 12),
      ];
      final secondSectionEpisodes = <EpisodeItem>[EpisodeItem(cid: 21)];
      final data = VideoDetailData(
        cid: 11,
        pages: <Part>[Part(cid: 11), Part(cid: 12)],
        ugcSeason: UgcSeason(
          sections: <SectionItem>[
            SectionItem(episodes: firstSectionEpisodes),
            SectionItem(episodes: secondSectionEpisodes),
          ],
        ),
      );

      expect(ugcSeasonPanelInitialCid(data, 99), 11);
      final selection = resolveUgcSeasonPanel(data, 11);
      expect(selection?.sectionIndex, 0);
      expect(selection?.episodes, same(firstSectionEpisodes));
      expect(hasRenderableUgcSeasonPanel(data, 99), isTrue);

      data.listOrder = ListOrder.desc;
      expect(ugcSeasonPanelInitialCid(data, 99), 12);
      expect(hasRenderableUgcSeasonPanel(data, 99), isTrue);

      data.pages = <Part>[Part(cid: 30)];
      expect(hasRenderableUgcSeasonPanel(data, 99), isFalse);

      data
        ..pages = null
        ..ugcSeason = UgcSeason(sections: <SectionItem>[]);
      expect(hasRenderableUgcSeasonPanel(data, 21), isFalse);
    });
  });
}

class _TransitionRegistryHarness extends StatefulWidget {
  const _TransitionRegistryHarness({super.key, required this.tag});

  final Object tag;

  @override
  State<_TransitionRegistryHarness> createState() =>
      _TransitionRegistryHarnessState();
}

class _TransitionRegistryHarnessState
    extends State<_TransitionRegistryHarness> {
  int _generation = 0;
  double _opacity = 1;
  double _width = 240;
  double _height = 160;
  double? _mediaClipHeight;
  BorderRadiusGeometry _borderRadius = const BorderRadius.all(
    Radius.circular(10),
  );
  VideoTransitionSourceLayout _layout =
      VideoTransitionSourceLayout.verticalCard;

  void recreateSource({
    double opacity = 1,
    double? width,
    double? height,
    double? mediaClipHeight,
    BorderRadiusGeometry? borderRadius,
    VideoTransitionSourceLayout? layout,
  }) {
    setState(() {
      _generation++;
      _opacity = opacity;
      _width = width ?? _width;
      _height = height ?? _height;
      _mediaClipHeight = mediaClipHeight ?? _mediaClipHeight;
      _borderRadius = borderRadius ?? _borderRadius;
      _layout = layout ?? _layout;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = VideoDetailHero.source(
      borderRadius: _borderRadius,
      flightChild: const ColoredBox(color: Colors.black),
      child: const ColoredBox(color: Colors.blue),
    );
    final mediaClipHeight = _mediaClipHeight;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 32,
            top: 80,
            width: _width,
            height: _height,
            child: Opacity(
              opacity: _opacity,
              child: VideoDetailTransitionSource(
                key: ValueKey(_generation),
                tag: widget.tag,
                borderRadius: _borderRadius,
                layout: _layout,
                child: mediaClipHeight == null
                    ? media
                    : ClipRect(
                        clipper: _TopStripClipper(height: mediaClipHeight),
                        child: media,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopStripClipper extends CustomClipper<Rect> {
  const _TopStripClipper({required this.height});

  final double height;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, height);

  @override
  bool shouldReclip(_TopStripClipper oldClipper) => oldClipper.height != height;
}
