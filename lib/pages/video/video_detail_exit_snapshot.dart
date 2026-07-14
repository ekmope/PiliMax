import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit_video/media_kit_video.dart';

const videoDetailExitVisualProviderKey = '_videoDetailExitVisualProvider';

typedef VideoDetailExitVisualProvider =
    VideoDetailExitVisual? Function(RenderBox transitionRoot);

/// Player geometry captured when a video-detail exit starts.
///
/// The detail page is snapshotted during the transition. This object paints a
/// second reference to the existing engine texture above that static image, so
/// video frames continue without creating another player session.
final class VideoDetailExitVisual {
  VideoDetailExitVisual({
    required this.playerRect,
    required this.clipRect,
    required this.controller,
    required this.fit,
    required this.alignment,
    required this.flipX,
    required this.flipY,
    this.aspectRatio,
    this.foregrounds = const [],
  });

  final Rect playerRect;
  final Rect clipRect;
  final VideoController controller;
  final BoxFit fit;
  final Alignment alignment;
  final bool flipX;
  final bool flipY;
  final double? aspectRatio;
  final List<VideoDetailExitForeground> foregrounds;

  bool get isUsable {
    return !playerRect.isEmpty &&
        playerRect.isFinite &&
        !clipRect.isEmpty &&
        clipRect.isFinite &&
        foregrounds.isNotEmpty &&
        controller.id.value != null &&
        controller.rect.value?.isEmpty == false;
  }

  Widget buildLiveTexture() => _VideoDetailLiveTexture(visual: this);

  void dispose() {
    for (final foreground in foregrounds) {
      foreground.image.dispose();
    }
  }
}

final class VideoDetailExitForeground {
  const VideoDetailExitForeground({
    required this.rect,
    required this.clipRect,
    required this.image,
  });

  final Rect rect;
  final Rect clipRect;
  final ui.Image image;

  Widget build() => IgnorePointer(
    child: RawImage(
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
    ),
  );
}

class VideoDetailExitCaptureBoundary extends SingleChildRenderObjectWidget {
  const VideoDetailExitCaptureBoundary({super.key, required super.child});

  @override
  VideoDetailExitCaptureRenderBox createRenderObject(BuildContext context) =>
      VideoDetailExitCaptureRenderBox();
}

class VideoDetailExitCaptureRenderBox extends RenderRepaintBoundary {
  ui.Image? captureSync({required double pixelRatio}) {
    final offsetLayer = layer;
    if (offsetLayer is! OffsetLayer || size.isEmpty) {
      return null;
    }
    return offsetLayer.toImageSync(
      Offset.zero & size,
      pixelRatio: pixelRatio,
    );
  }
}

VideoDetailExitForeground? captureVideoDetailExitForeground({
  required GlobalKey boundaryKey,
  required RenderBox transitionRoot,
  required double pixelRatio,
  required Rect clipRect,
}) {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! VideoDetailExitCaptureRenderBox ||
      !renderObject.attached ||
      !transitionRoot.attached ||
      renderObject.size.isEmpty) {
    return null;
  }
  try {
    final rect = MatrixUtils.transformRect(
      renderObject.getTransformTo(transitionRoot),
      Offset.zero & renderObject.size,
    );
    final image = renderObject.captureSync(pixelRatio: pixelRatio);
    if (image == null) {
      return null;
    }
    return VideoDetailExitForeground(
      rect: rect,
      clipRect: rect.intersect(clipRect),
      image: image,
    );
  } catch (_) {
    return null;
  }
}

class _VideoDetailLiveTexture extends StatelessWidget {
  const _VideoDetailLiveTexture({required this.visual});

  final VideoDetailExitVisual visual;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        clipBehavior: Clip.hardEdge,
        child: Transform.flip(
          flipX: visual.flipX,
          flipY: visual.flipY,
          child: FittedBox(
            fit: visual.fit,
            alignment: visual.alignment,
            child: SimpleVideo(
              key: ValueKey(('video-exit-texture', visual.controller.hashCode)),
              controller: visual.controller,
              aspectRatio: visual.aspectRatio,
            ),
          ),
        ),
      ),
    );
  }
}
