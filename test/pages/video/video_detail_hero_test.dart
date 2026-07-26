import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero_curve.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_ugc_title_height_cache.dart';
import 'package:PiliMax/models/common/list_order.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart';
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/models_new/video/video_detail/section.dart';
import 'package:PiliMax/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
