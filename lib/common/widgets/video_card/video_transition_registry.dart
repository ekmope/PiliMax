import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const videoTransitionTokenKey = '_videoTransitionToken';

final class VideoTransitionToken {
  VideoTransitionToken({
    required this.tag,
    required this.sourceGeneration,
    required this.sourceRoute,
    required this.launchRect,
    required this.contentKey,
    required this.coverUrl,
    required Future<ui.Image?> snapshot,
  }) : _snapshotFuture = snapshot {
    _snapshotFuture.then((image) {
      if (_disposed) {
        image?.dispose();
      } else {
        _snapshot = image;
        if (image != null) {
          VideoTransitionRegistry._retainTokenSnapshot(this, image);
        }
      }
    });
  }

  final Object tag;
  final int sourceGeneration;
  final Route<dynamic>? sourceRoute;
  final Rect launchRect;
  String contentKey;
  final String? coverUrl;
  final Future<ui.Image?> _snapshotFuture;

  ui.Image? _snapshot;
  bool _disposed = false;

  ui.Image? get snapshot => _snapshot;

  void bindLaunchContentKey(String contentKey) {
    if (!_disposed) {
      this.contentKey = contentKey;
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _discardSnapshot();
  }

  void _discardSnapshot() {
    final image = _snapshot;
    if (image == null) {
      return;
    }
    _snapshot = null;
    VideoTransitionRegistry._forgetTokenSnapshot(this, image);
    image.dispose();
  }
}

final class VideoReturnTarget {
  const VideoReturnTarget({
    required this.rect,
    required this.borderRadius,
    required this.snapshot,
    required this.coverUrl,
  });

  final Rect rect;
  final BorderRadius borderRadius;
  final ui.Image? snapshot;
  final String? coverUrl;
}

final class VideoTransitionRegistration {
  VideoTransitionRegistration._(this._tag, this._generation);

  final Object _tag;
  final int _generation;
  bool _disposed = false;

  void prepare() {
    if (!_disposed) {
      VideoTransitionRegistry._prepare(_tag, _generation);
    }
  }

  void attachMedia(GlobalKey boundaryKey) {
    if (!_disposed) {
      VideoTransitionRegistry._attachMedia(
        _tag,
        _generation,
        boundaryKey,
      );
    }
  }

  void detachMedia(GlobalKey boundaryKey) {
    if (!_disposed) {
      VideoTransitionRegistry._detachMedia(
        _tag,
        _generation,
        boundaryKey,
      );
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    VideoTransitionRegistry._unregister(_tag, _generation);
  }
}

final class _VideoTransitionSource {
  _VideoTransitionSource({
    required this.generation,
    required this.boundaryKey,
    required this.route,
    required this.borderRadius,
  });

  final int generation;
  final GlobalKey boundaryKey;
  final Route<dynamic>? route;
  final BorderRadiusGeometry borderRadius;
  GlobalKey? _mediaBoundaryKey;
  Future<ui.Image?>? _preparedSnapshot;
  Timer? _preparedSnapshotExpiry;

  BuildContext? get context => boundaryKey.currentContext;

  BuildContext? get mediaContext => _mediaBoundaryKey?.currentContext;

  bool get hasPreparedSnapshot => _preparedSnapshot != null;

  Rect? currentRect() {
    return _rectFor(context);
  }

  Rect? currentMediaRect() {
    return _rectFor(mediaContext);
  }

  static Rect? _rectFor(BuildContext? context) {
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void attachMedia(GlobalKey boundaryKey) {
    if (identical(_mediaBoundaryKey, boundaryKey)) {
      return;
    }
    assert(
      _mediaBoundaryKey == null,
      'A video transition source can only have one media Hero.',
    );
    _mediaBoundaryKey = boundaryKey;
  }

  void detachMedia(GlobalKey boundaryKey) {
    if (identical(_mediaBoundaryKey, boundaryKey)) {
      _mediaBoundaryKey = null;
    }
  }

  BorderRadius resolvedBorderRadius() {
    final direction = context == null
        ? TextDirection.ltr
        : Directionality.maybeOf(context!) ?? TextDirection.ltr;
    return borderRadius.resolve(direction);
  }

  void prepareSnapshot() {
    if (_preparedSnapshot != null) {
      return;
    }
    final snapshot = _capture();
    _preparedSnapshot = snapshot;
    _preparedSnapshotExpiry = Timer(const Duration(seconds: 4), () {
      if (!identical(_preparedSnapshot, snapshot)) {
        return;
      }
      _preparedSnapshot = null;
      snapshot.then((image) => image?.dispose());
    });
  }

  Future<ui.Image?> takeSnapshot() {
    _preparedSnapshotExpiry?.cancel();
    _preparedSnapshotExpiry = null;
    final snapshot = _preparedSnapshot;
    _preparedSnapshot = null;
    return snapshot ?? _capture();
  }

  void discardPreparedSnapshot() {
    _preparedSnapshotExpiry?.cancel();
    _preparedSnapshotExpiry = null;
    final snapshot = _preparedSnapshot;
    _preparedSnapshot = null;
    snapshot?.then((image) => image?.dispose());
  }

  Future<ui.Image?> _capture() async {
    var renderObject = context?.findRenderObject();
    if (renderObject is RenderRepaintBoundary &&
        renderObject.attached &&
        renderObject.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
      renderObject = context?.findRenderObject();
    }
    if (renderObject is! RenderRepaintBoundary ||
        !renderObject.attached ||
        renderObject.debugNeedsPaint) {
      return null;
    }
    final requestedPixelRatio = context == null
        ? 1.0
        : MediaQuery.devicePixelRatioOf(context!).clamp(1.0, 1.5);
    final logicalPixels = renderObject.size.width * renderObject.size.height;
    final areaLimitedRatio = logicalPixels <= 0
        ? 1.0
        : math.sqrt(1500000 / logicalPixels);
    final devicePixelRatio = math
        .min(requestedPixelRatio, areaLimitedRatio)
        .clamp(0.5, 1.5);
    try {
      return await renderObject.toImage(pixelRatio: devicePixelRatio);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _mediaBoundaryKey = null;
    discardPreparedSnapshot();
  }
}

abstract final class VideoTransitionRegistry {
  static const _maximumPreparedSnapshots = 3;
  static const _maximumRetainedSnapshotPixels = 4500000;

  static final Map<Object, List<_VideoTransitionSource>> _sources = {};
  static final List<_VideoTransitionSource> _preparedSources = [];
  static final List<VideoTransitionToken> _tokensWithSnapshots = [];
  static int _nextGeneration = 0;
  static int _retainedSnapshotPixels = 0;

  static VideoTransitionRegistration register({
    required Object tag,
    required GlobalKey boundaryKey,
    required BuildContext context,
    required BorderRadiusGeometry borderRadius,
  }) {
    final generation = _nextGeneration++;
    final source = _VideoTransitionSource(
      generation: generation,
      boundaryKey: boundaryKey,
      route: ModalRoute.of(context),
      borderRadius: borderRadius,
    );
    (_sources[tag] ??= []).add(source);
    return VideoTransitionRegistration._(tag, generation);
  }

  static void prepare(Object tag) {
    final source = _findLaunchSource(tag);
    if (source != null) {
      _prepareSource(source);
    }
  }

  static void _prepare(Object tag, int generation) {
    final source = _sourceByGeneration(tag, generation);
    if (source != null) {
      _prepareSource(source);
    }
  }

  static VideoTransitionToken? claim({
    required Object tag,
    required String contentKey,
    required String? coverUrl,
  }) {
    final source = _findLaunchSource(tag);
    final rect = source?.currentRect();
    final mediaRect = source?.currentMediaRect();
    if (source == null ||
        rect == null ||
        mediaRect == null ||
        source.route?.isCurrent != true ||
        !_isVisible(source.context, rect) ||
        !_isVisible(source.mediaContext, mediaRect)) {
      return null;
    }
    final snapshot = source.takeSnapshot();
    _preparedSources.remove(source);
    return VideoTransitionToken(
      tag: tag,
      sourceGeneration: source.generation,
      sourceRoute: source.route,
      launchRect: rect,
      contentKey: contentKey,
      coverUrl: coverUrl,
      snapshot: snapshot,
    );
  }

  static VideoReturnTarget? resolveReturn(VideoTransitionToken token) {
    final source = _sourceByGeneration(
      token.tag,
      token.sourceGeneration,
    );
    final rect = source?.currentRect();
    final snapshot = token.snapshot;
    final launchAspectRatio = token.launchRect.width / token.launchRect.height;
    final returnAspectRatio = rect == null ? 0 : rect.width / rect.height;
    final aspectRatioChanged =
        returnAspectRatio <= 0 ||
        (launchAspectRatio - returnAspectRatio).abs() / launchAspectRatio >
            0.08;
    if (source == null ||
        rect == null ||
        aspectRatioChanged ||
        !identical(source.route, token.sourceRoute) ||
        source.route?.isActive != true ||
        !_isVisible(source.context, rect)) {
      return null;
    }
    return VideoReturnTarget(
      rect: rect,
      borderRadius: source.resolvedBorderRadius(),
      snapshot: snapshot,
      coverUrl: token.coverUrl,
    );
  }

  static bool _isVisible(BuildContext? context, Rect rect) {
    if (context == null) {
      return false;
    }
    if (rect.width <= 0 || rect.height <= 0) {
      return false;
    }
    final visible = _visiblePortion(context, rect);
    if (visible == null) {
      return false;
    }
    final visibleRatio =
        (visible.width * visible.height) / (rect.width * rect.height);
    return visibleRatio >= 0.2;
  }

  static Rect? _visiblePortion(BuildContext context, Rect rect) {
    final viewport = Offset.zero & MediaQuery.sizeOf(context);
    if (!rect.overlaps(viewport)) {
      return null;
    }
    var visible = rect.intersect(viewport);
    RenderObject? child = context.findRenderObject();
    while (child != null) {
      final parent = child.parent;
      if (parent == null) {
        break;
      }
      if (parent is RenderOffstage && parent.offstage) {
        return null;
      }
      if (parent is RenderOpacity && parent.opacity <= 0.01) {
        return null;
      }
      if (parent is RenderIndexedStack &&
          !_isDisplayedIndexedStackChild(parent, child)) {
        return null;
      }
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        final globalClip = MatrixUtils.transformRect(
          parent.getTransformTo(null),
          clip,
        );
        if (!visible.overlaps(globalClip)) {
          return null;
        }
        visible = visible.intersect(globalClip);
      }
      child = parent;
    }
    return visible;
  }

  static bool _isDisplayedIndexedStackChild(
    RenderIndexedStack stack,
    RenderObject child,
  ) {
    final index = stack.index;
    if (index == null) {
      return false;
    }
    RenderBox? displayedChild = stack.firstChild;
    for (var i = 0; i < index && displayedChild != null; i++) {
      displayedChild = stack.childAfter(displayedChild);
    }
    return identical(displayedChild, child);
  }

  static _VideoTransitionSource? _findLaunchSource(Object tag) {
    final sources = _sources[tag];
    if (sources == null) {
      return null;
    }
    for (final requirePrepared in [true, false]) {
      for (final source in sources.reversed) {
        final rect = source.currentRect();
        final mediaRect = source.currentMediaRect();
        if (source.route?.isCurrent == true &&
            (!requirePrepared || source.hasPreparedSnapshot) &&
            rect != null &&
            mediaRect != null &&
            _isVisible(source.context, rect) &&
            _isVisible(source.mediaContext, mediaRect)) {
          return source;
        }
      }
    }
    return null;
  }

  static _VideoTransitionSource? _sourceByGeneration(
    Object tag,
    int generation,
  ) {
    final sources = _sources[tag];
    if (sources == null) {
      return null;
    }
    for (final source in sources.reversed) {
      if (source.generation == generation) {
        return source;
      }
    }
    return null;
  }

  static void _prepareSource(_VideoTransitionSource source) {
    _preparedSources.removeWhere((item) => !item.hasPreparedSnapshot);
    source.prepareSnapshot();
    _preparedSources
      ..remove(source)
      ..add(source);
    while (_preparedSources.length > _maximumPreparedSnapshots) {
      _preparedSources.removeAt(0).discardPreparedSnapshot();
    }
  }

  static void _attachMedia(
    Object tag,
    int generation,
    GlobalKey boundaryKey,
  ) {
    _sourceByGeneration(tag, generation)?.attachMedia(boundaryKey);
  }

  static void _detachMedia(
    Object tag,
    int generation,
    GlobalKey boundaryKey,
  ) {
    _sourceByGeneration(tag, generation)?.detachMedia(boundaryKey);
  }

  static void _retainTokenSnapshot(
    VideoTransitionToken token,
    ui.Image image,
  ) {
    _tokensWithSnapshots.add(token);
    _retainedSnapshotPixels += image.width * image.height;
    while (_retainedSnapshotPixels > _maximumRetainedSnapshotPixels &&
        _tokensWithSnapshots.isNotEmpty) {
      _tokensWithSnapshots.first._discardSnapshot();
    }
  }

  static void _forgetTokenSnapshot(
    VideoTransitionToken token,
    ui.Image image,
  ) {
    if (_tokensWithSnapshots.remove(token)) {
      _retainedSnapshotPixels -= image.width * image.height;
    }
  }

  static void _unregister(Object tag, int generation) {
    final sources = _sources[tag];
    if (sources == null) {
      return;
    }
    final index = sources.indexWhere(
      (source) => source.generation == generation,
    );
    if (index < 0) {
      return;
    }
    final source = sources.removeAt(index);
    _preparedSources.remove(source);
    source.dispose();
    if (sources.isEmpty) {
      _sources.remove(tag);
    }
  }
}
