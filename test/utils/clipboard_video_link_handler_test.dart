import 'package:PiliMax/utils/clipboard_video_link_handler.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractVideoLink', () {
    test('extracts direct video links and trims surrounding punctuation', () {
      expect(
        ClipboardVideoLinkHandler.extractVideoLink(
          '看看这个：https://www.bilibili.com/video/BV17x411w7KC?p=1。',
        ),
        'https://www.bilibili.com/video/BV17x411w7KC?p=1',
      );
      expect(
        ClipboardVideoLinkHandler.extractVideoLink(
          'b23.tv/AbC123）',
        ),
        'b23.tv/AbC123',
      );
    });

    test('requires an exact official domain boundary and video path', () {
      expect(
        ClipboardVideoLinkHandler.extractVideoLink(
          'https://notbilibili.com/video/BV17x411w7KC',
        ),
        isNull,
      );
      expect(
        ClipboardVideoLinkHandler.extractVideoLink(
          'https://www.bilibili.com.evil.tv/video/BV17x411w7KC',
        ),
        isNull,
      );
      expect(
        ClipboardVideoLinkHandler.extractVideoLink(
          'https://www.bilibili.com/read/cv123',
        ),
        isNull,
      );
      expect(
        ClipboardVideoLinkHandler.extractVideoLink(
          'https://www.bilibili.com/video/BV17x411w7KC/extra',
        ),
        isNull,
      );
    });
  });

  group('resolveVideoUrl', () {
    test('accepts a b23 redirect only when it resolves to a video', () async {
      const videoUrl = 'https://www.bilibili.com/video/BV17x411w7KC?p=1';
      expect(
        await ClipboardVideoLinkHandler.resolveVideoUrl(
          'https://b23.tv/AbC123',
          redirectResolver: (_) async => videoUrl,
        ),
        videoUrl,
      );
      expect(
        await ClipboardVideoLinkHandler.resolveVideoUrl(
          'https://b23.tv/AbC123',
          redirectResolver: (_) async => 'https://www.bilibili.com/read/cv123',
        ),
        isNull,
      );
      expect(
        await ClipboardVideoLinkHandler.resolveVideoUrl(
          'https://b23.tv/AbC123',
          redirectResolver: (_) async =>
              'https://notbilibili.com/video/BV17x411w7KC',
        ),
        isNull,
      );
    });
  });

  test('canonicalizes AV and BV variants for duplicate throttling', () {
    const aid = 170001;
    final bvid = IdUtils.av2bv(aid);

    expect(
      ClipboardVideoLinkHandler.canonicalVideoKey(
        'https://www.bilibili.com/video/av$aid',
      ),
      'aid:$aid',
    );
    expect(
      ClipboardVideoLinkHandler.canonicalVideoKey(
        'https://m.bilibili.com/video/$bvid',
      ),
      'aid:$aid',
    );
  });

  group('current video identity', () {
    test('prefers live detail controller ids over stale route arguments', () {
      const liveAid = 170001;
      const staleAid = 170002;

      expect(
        ClipboardVideoLinkHandler.resolveCurrentVideoKey(
          detailAid: liveAid,
          detailBvid: IdUtils.av2bv(liveAid),
          routeAid: staleAid,
          routeBvid: IdUtils.av2bv(staleAid),
        ),
        'aid:$liveAid',
      );
    });

    test('falls back to the live UGC and PGC intro ids', () {
      const ugcAid = 170003;
      const pgcAid = 170004;

      expect(
        ClipboardVideoLinkHandler.resolveCurrentVideoKey(
          ugcBvid: IdUtils.av2bv(ugcAid),
          routeAid: 999999,
        ),
        'aid:$ugcAid',
      );
      expect(
        ClipboardVideoLinkHandler.resolveCurrentVideoKey(
          pgcBvid: IdUtils.av2bv(pgcAid),
          routeAid: 999999,
        ),
        'aid:$pgcAid',
      );
    });

    test('uses route arguments only when no live controller id exists', () {
      const routeAid = 170005;

      expect(
        ClipboardVideoLinkHandler.resolveCurrentVideoKey(routeAid: routeAid),
        'aid:$routeAid',
      );
    });
  });

  group('navigation guard', () {
    test('rejects lifecycle generation and route identity changes', () {
      final arguments = <String, Object?>{'heroTag': 'video-a'};
      final routeObject = Object();
      expect(
        ClipboardVideoLinkHandler.navigationGuardMatches(
          initialized: true,
          resumed: true,
          expectedGeneration: 4,
          currentGeneration: 4,
          expectedRoute: '/search?keyword=one',
          currentRoute: '/search',
          expectedRouteObject: routeObject,
          currentRouteObject: routeObject,
          expectedArguments: arguments,
          currentArguments: arguments,
        ),
        isTrue,
      );
      expect(
        ClipboardVideoLinkHandler.navigationGuardMatches(
          initialized: true,
          resumed: true,
          expectedGeneration: 4,
          currentGeneration: 5,
          expectedRoute: '/search',
          currentRoute: '/search',
          expectedRouteObject: routeObject,
          currentRouteObject: Object(),
          expectedArguments: arguments,
          currentArguments: arguments,
        ),
        isFalse,
      );
      expect(
        ClipboardVideoLinkHandler.navigationGuardMatches(
          initialized: true,
          resumed: true,
          expectedGeneration: 4,
          currentGeneration: 4,
          expectedRoute: '/search',
          currentRoute: '/settings',
          expectedArguments: arguments,
          currentArguments: arguments,
        ),
        isFalse,
      );
      expect(
        ClipboardVideoLinkHandler.navigationGuardMatches(
          initialized: true,
          resumed: true,
          expectedGeneration: 4,
          currentGeneration: 4,
          expectedRoute: '/search',
          currentRoute: '/search',
          expectedArguments: arguments,
          currentArguments: <String, Object?>{'heroTag': 'video-b'},
        ),
        isFalse,
      );
    });

    test('rejects a live video switch on the same route', () {
      final arguments = <String, Object?>{'heroTag': 'video-a'};
      expect(
        ClipboardVideoLinkHandler.navigationGuardMatches(
          initialized: true,
          resumed: true,
          expectedGeneration: 8,
          currentGeneration: 8,
          expectedRoute: '/videoV',
          currentRoute: '/videoV',
          expectedArguments: arguments,
          currentArguments: arguments,
          expectedVideoKey: 'aid:170001',
          currentVideoKey: 'aid:170002',
        ),
        isFalse,
      );
    });
  });

  test('only successful navigation records the clipboard text', () {
    expect(
      ClipboardVideoLinkHandler.clipboardTextAfterNavigation(
        previousText: null,
        candidateText: 'https://www.bilibili.com/video/av170001',
        navigationSucceeded: false,
      ),
      isNull,
    );
    expect(
      ClipboardVideoLinkHandler.clipboardTextAfterNavigation(
        previousText: null,
        candidateText: 'https://www.bilibili.com/video/av170001',
        navigationSucceeded: true,
      ),
      'https://www.bilibili.com/video/av170001',
    );
  });
}
