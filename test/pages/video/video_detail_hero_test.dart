import 'package:PiliMax/common/widgets/video_card/video_detail_hero_curve.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_ugc_title_height_cache.dart';
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
}
