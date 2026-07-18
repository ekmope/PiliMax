import 'dart:async';
import 'dart:ui' as ui;

import 'package:PiliMax/plugin/pl_player/preview_request_coordinator.dart';
import 'package:PiliMax/plugin/pl_player/view/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _PreviewValue {
  bool disposed = false;
}

Future<ui.Image> _image(Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(2, 2);
}

void main() {
  test('stale preview completion cannot overwrite a repeated URL', () async {
    const url = 'https://example.test/sprite.jpg';
    const coordinator = PreviewLoadCoordinator<_PreviewValue>();
    final epoch = PreviewRequestEpoch();
    final cache = <String, _PreviewValue?>{};
    final staleLoad = Completer<_PreviewValue?>();
    final currentLoad = Completer<_PreviewValue?>();
    final staleToken = epoch.capture(url);

    final staleCompletion = coordinator.load(
      token: staleToken,
      cache: cache,
      isRequestCurrent: epoch.isCurrent,
      canRetain: () => true,
      loader: (_) => staleLoad.future,
      disposeValue: (value) => value.disposed = true,
    );
    expect(cache, containsPair(url, null));

    epoch.invalidate();
    cache.clear();
    final currentToken = epoch.capture(url);
    final currentCompletion = coordinator.load(
      token: currentToken,
      cache: cache,
      isRequestCurrent: epoch.isCurrent,
      canRetain: () => true,
      loader: (_) => currentLoad.future,
      disposeValue: (value) => value.disposed = true,
    );

    final currentValue = _PreviewValue();
    currentLoad.complete(currentValue);
    expect(await currentCompletion, same(currentValue));
    expect(cache[url], same(currentValue));

    final staleValue = _PreviewValue();
    staleLoad.complete(staleValue);
    expect(await staleCompletion, isNull);
    expect(staleValue.disposed, isTrue);
    expect(cache[url], same(currentValue));
  });

  testWidgets(
    'VideoShotImage rejects a stale same-URL generation',
    (tester) async {
      const url = 'https://example.test/sprite.jpg';
      final epoch = PreviewRequestEpoch();
      final imageCache = <String, ui.Image?>{};
      final staleLoad = Completer<ui.Image?>();
      final currentLoad = Completer<ui.Image?>();
      var loadCount = 0;

      Future<ui.Image?> loader(String _) {
        loadCount++;
        return loadCount == 1 ? staleLoad.future : currentLoad.future;
      }

      Widget preview(PreviewRequestToken token) => MaterialApp(
        home: Center(
          child: VideoShotImage(
            key: const ValueKey('preview'),
            imageCache: imageCache,
            url: url,
            x: 0,
            y: 0,
            imgXSize: 2,
            imgYSize: 2,
            height: 20,
            onSetSize: (_, _) {},
            isMounted: () => true,
            requestToken: token,
            isRequestCurrent: epoch.isCurrent,
            imageLoader: loader,
          ),
        ),
      );

      final staleToken = epoch.capture(url);
      await tester.pumpWidget(preview(staleToken));
      expect(loadCount, 1);

      epoch.invalidate();
      imageCache.clear();
      final currentToken = epoch.capture(url);
      await tester.pumpWidget(preview(currentToken));
      expect(loadCount, 2);

      final currentImage = await _image(Colors.green);
      currentLoad.complete(currentImage);
      await tester.pump();
      expect(identical(imageCache[url], currentImage), isTrue);

      final staleImage = await _image(Colors.red);
      staleLoad.complete(staleImage);
      await tester.pump();
      expect(identical(imageCache[url], currentImage), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      currentImage.dispose();
    },
  );
}
