import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit_video/media_kit_video.dart';

const videoDetailExitVisualProviderKey = '_videoDetailExitVisualProvider';

typedef VideoDetailExitVisualProvider = VideoDetailExitVisual? Function(
  RenderBox transitionRoot,
);

/// Playing detail pages use one snapshot for the non-media layers while the
/// decoded video texture remains live above it. This keeps predictive-back
/// frames from repainting the full player, danmaku, and control tree.
abstract final class VideoDetailExitSnapshotPolicy {
  static bool shouldCapture({required bool isPlaying}) => isPlaying;
}

/// Player geometry captured when a video-detail exit starts.
///
/// This remains available for fallback callers and for the live media layer
/// used above the playing-page snapshot.
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
    this.fallbackCover,
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

  /// The detail poster used only for the final same-rect media handoff.
  ///
  /// It is deliberately kept out of the page snapshot. Rendering it inside
  /// the transition media surface prevents a second, independently animated
  /// full-screen cover from appearing behind the live texture.
  final String? fallbackCover;
  final List<VideoDetailExitForeground> foregrounds;

  bool get isUsable {
    // Foregrounds are optional. The frozen page plus the existing live video
    // texture still form a valid exit visual when a decorative capture fails.
    return !playerRect.isEmpty &&
        playerRect.isFinite &&
        !clipRect.isEmpty &&
        clipRect.isFinite &&
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

enum VideoDetailExitForegroundRole { media, body }

final class VideoDetailExitForeground {
  const VideoDetailExitForeground({
    required this.role,
    required this.rect,
    required this.clipRect,
    required this.image,
  });

  final VideoDetailExitForegroundRole role;
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

// Keep synchronous captures small enough for the first predictive-back frame.
// A 600k RGBA image is about 2.3 MiB before engine-side overhead.
const double _maxExitCapturePixelRatio = 1.25;
const double _maxExitCapturePhysicalPixels = 600000;

double _exitCapturePixelRatio({
  required Size logicalSize,
  required double devicePixelRatio,
}) {
  final safeDevicePixelRatio = devicePixelRatio.isFinite
      ? devicePixelRatio.clamp(1.0, _maxExitCapturePixelRatio).toDouble()
      : 1.0;
  final logicalPixels = logicalSize.width * logicalSize.height;
  if (!logicalPixels.isFinite || logicalPixels <= 0) {
    return 1.0;
  }
  final budgetedPixelRatio = math
      .sqrt(_maxExitCapturePhysicalPixels / logicalPixels)
      .clamp(1.0, _maxExitCapturePixelRatio)
      .toDouble();
  return math.min(safeDevicePixelRatio, budgetedPixelRatio);
}

VideoDetailExitForeground? captureVideoDetailExitForeground({
  required VideoDetailExitForegroundRole role,
  required GlobalKey boundaryKey,
  required RenderBox transitionRoot,
  required double devicePixelRatio,
  required Rect clipRect,
}) {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! VideoDetailExitCaptureRenderBox ||
      !renderObject.attached ||
      !transitionRoot.attached ||
      renderObject.size.isEmpty ||
      clipRect.isEmpty ||
      !clipRect.isFinite) {
    return null;
  }
  try {
    final pixelRatio = _exitCapturePixelRatio(
      logicalSize: renderObject.size,
      devicePixelRatio: devicePixelRatio,
    );
    final rect = MatrixUtils.transformRect(
      renderObject.getTransformTo(transitionRoot),
      Offset.zero & renderObject.size,
    );
    final image = renderObject.captureSync(pixelRatio: pixelRatio);
    if (image == null) {
      return null;
    }
    return VideoDetailExitForeground(
      role: role,
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
            // Predictive return must preserve the decoded frame rather than
            // applying the user's playback crop mode to the source card.
            fit: BoxFit.contain,
            alignment: visual.alignment,
            child: SimpleVideo(
              key: ValueKey(('video-exit-texture', visual.controller.hashCode)),
              controller: visual.controller,
              aspectRatio: null,
            ),
          ),
        ),
      ),
    );
  }
}
