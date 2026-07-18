import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const videoTransitionTokenKey = '_videoTransitionToken';

enum VideoTransitionSourceLayout { verticalCard, horizontalRow, embedded }

final class VideoTransitionTitleDescriptor {
  const VideoTransitionTitleDescriptor({
    required this.text,
    this.textSpan,
    this.style,
    this.maxLines,
    this.textAlign,
    this.overflow,
  });

  final String text;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
}

final class VideoTransitionTitleSnapshot {
  const VideoTransitionTitleSnapshot({
    required this.rect,
    required this.text,
    required this.textSpan,
    required this.style,
    required this.maxLines,
    required this.textAlign,
    required this.overflow,
    required this.textDirection,
    required this.textScaler,
  });

  final Rect rect;
  final String text;
  final InlineSpan? textSpan;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final TextDirection textDirection;
  final TextScaler textScaler;
}

final class VideoTransitionToken {
  VideoTransitionToken({
    required this.tag,
    required this.sourceGeneration,
    required this.sourceRoute,
    required this.launchRect,
    required this.sourceVisibleRect,
    required this.mediaLaunchRect,
    required this.mediaLaunchBorderRadius,
    required this.launchBorderRadius,
    required this.sourceLayout,
    required this.sourceSurfaceColor,
    required this.title,
    required this.contentKey,
  });

  final Object tag;
  final int sourceGeneration;
  final Route<dynamic>? sourceRoute;
  final Rect launchRect;
  final Rect sourceVisibleRect;
  final Rect mediaLaunchRect;
  final BorderRadius mediaLaunchBorderRadius;
  final BorderRadius launchBorderRadius;
  final VideoTransitionSourceLayout sourceLayout;
  final Color sourceSurfaceColor;
  final VideoTransitionTitleSnapshot? title;
  String contentKey;
  bool _disposed = false;

  void bindLaunchContentKey(String contentKey) {
    if (!_disposed) {
      this.contentKey = contentKey;
    }
  }

  void dispose() {
    _disposed = true;
  }
}

final class VideoReturnTarget {
  const VideoReturnTarget({
    required this.rect,
    required this.visibleRect,
    required this.borderRadius,
    required this.layout,
    this.mediaRect,
    this.mediaVisibleRect,
    this.mediaBorderRadius,
  });

  final Rect rect;
  final Rect visibleRect;
  final BorderRadius borderRadius;
  final VideoTransitionSourceLayout layout;
  final Rect? mediaRect;
  final Rect? mediaVisibleRect;
  final BorderRadius? mediaBorderRadius;

  bool get hasMediaTarget =>
      mediaRect?.isEmpty == false && mediaVisibleRect?.isEmpty == false;
}

final class VideoTransitionRegistration {
  VideoTransitionRegistration._(this._tag, this._generation);

  final Object _tag;
  final int _generation;
  bool _disposed = false;

  Rect? currentVisibleRect() => _disposed
      ? null
      : VideoTransitionRegistry._currentVisibleRect(_tag, _generation);

  void notePointerDown(Offset position) {
    if (!_disposed) {
      VideoTransitionRegistry._notePointerDown(
        _tag,
        _generation,
        position,
      );
    }
  }

  void attachMedia(
    GlobalKey boundaryKey,
    BorderRadiusGeometry borderRadius,
  ) {
    if (!_disposed) {
      VideoTransitionRegistry._attachMedia(
        _tag,
        _generation,
        boundaryKey,
        borderRadius,
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

  void attachTitle(
    GlobalKey boundaryKey,
    VideoTransitionTitleDescriptor descriptor,
  ) {
    if (!_disposed) {
      VideoTransitionRegistry._attachTitle(
        _tag,
        _generation,
        boundaryKey,
        descriptor,
      );
    }
  }

  void detachTitle(GlobalKey boundaryKey) {
    if (!_disposed) {
      VideoTransitionRegistry._detachTitle(
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
    required this.layout,
  });

  final int generation;
  final GlobalKey boundaryKey;
  final Route<dynamic>? route;
  final BorderRadiusGeometry borderRadius;
  final VideoTransitionSourceLayout layout;
  GlobalKey? _mediaBoundaryKey;
  BorderRadiusGeometry? _mediaBorderRadius;
  GlobalKey? _titleBoundaryKey;
  VideoTransitionTitleDescriptor? _titleDescriptor;
  Offset? _lastPointerPosition;
  Rect? _launchVisibleFraction;

  BuildContext? get context => boundaryKey.currentContext;

  BuildContext? get mediaContext => _mediaBoundaryKey?.currentContext;

  BuildContext? get titleContext => _titleBoundaryKey?.currentContext;

  Rect? currentRect() {
    return _rectFor(context);
  }

  Rect? currentMediaRect() {
    return _rectFor(mediaContext);
  }

  Rect? currentMediaVisibleRect() {
    final rect = currentMediaRect();
    final currentContext = mediaContext;
    if (rect == null || currentContext == null) {
      return null;
    }
    return VideoTransitionRegistry._visiblePortion(currentContext, rect);
  }

  Rect? currentVisibleRect() {
    final rect = currentRect();
    final currentContext = context;
    if (rect == null || currentContext == null) {
      return null;
    }
    final visible = VideoTransitionRegistry._visiblePortion(
      currentContext,
      rect,
    );
    final fraction = _launchVisibleFraction;
    if (visible == null || fraction == null) {
      return visible;
    }
    final launchVisible = Rect.fromLTRB(
      rect.left + rect.width * fraction.left,
      rect.top + rect.height * fraction.top,
      rect.left + rect.width * fraction.right,
      rect.top + rect.height * fraction.bottom,
    );
    return visible.intersect(launchVisible);
  }

  Rect? currentLaunchVisibleRect() {
    final rect = currentRect();
    final currentContext = context;
    if (rect == null || currentContext == null) {
      return null;
    }
    final ancestorVisible = VideoTransitionRegistry._visiblePortion(
      currentContext,
      rect,
    );
    if (ancestorVisible == null) {
      return null;
    }
    final visible = VideoTransitionRegistry._trimSiblingOcclusion(
      currentContext,
      rect,
      ancestorVisible,
      _lastPointerPosition,
    );
    _launchVisibleFraction = Rect.fromLTRB(
      ((visible.left - rect.left) / rect.width).clamp(0.0, 1.0),
      ((visible.top - rect.top) / rect.height).clamp(0.0, 1.0),
      ((visible.right - rect.left) / rect.width).clamp(0.0, 1.0),
      ((visible.bottom - rect.top) / rect.height).clamp(0.0, 1.0),
    );
    return visible;
  }

  void notePointerDown(Offset position) {
    _lastPointerPosition = position;
    _launchVisibleFraction = null;
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

  void attachMedia(
    GlobalKey boundaryKey,
    BorderRadiusGeometry borderRadius,
  ) {
    if (!identical(_mediaBoundaryKey, boundaryKey)) {
      assert(
        _mediaBoundaryKey == null,
        'A video transition source can only have one media Hero.',
      );
      _mediaBoundaryKey = boundaryKey;
    }
    _mediaBorderRadius = borderRadius;
  }

  void detachMedia(GlobalKey boundaryKey) {
    if (identical(_mediaBoundaryKey, boundaryKey)) {
      _mediaBoundaryKey = null;
      _mediaBorderRadius = null;
    }
  }

  void attachTitle(
    GlobalKey boundaryKey,
    VideoTransitionTitleDescriptor descriptor,
  ) {
    if (!identical(_titleBoundaryKey, boundaryKey)) {
      assert(
        _titleBoundaryKey == null,
        'A video transition source can only have one title anchor.',
      );
      _titleBoundaryKey = boundaryKey;
    }
    _titleDescriptor = descriptor;
  }

  void detachTitle(GlobalKey boundaryKey) {
    if (identical(_titleBoundaryKey, boundaryKey)) {
      _titleBoundaryKey = null;
      _titleDescriptor = null;
    }
  }

  VideoTransitionTitleSnapshot? currentTitleSnapshot() {
    final descriptor = _titleDescriptor;
    final context = titleContext;
    final rect = _rectFor(context);
    if (descriptor == null || context == null || rect == null) {
      return null;
    }
    final defaultTextStyle = DefaultTextStyle.of(context);
    return VideoTransitionTitleSnapshot(
      rect: rect,
      text: descriptor.text,
      textSpan: descriptor.textSpan,
      style: defaultTextStyle.style.merge(descriptor.style),
      maxLines: descriptor.maxLines ?? defaultTextStyle.maxLines,
      textAlign: descriptor.textAlign ?? defaultTextStyle.textAlign,
      overflow: descriptor.overflow ?? defaultTextStyle.overflow,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler:
          MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling,
    );
  }

  BorderRadius resolvedBorderRadius() {
    final direction = context == null
        ? TextDirection.ltr
        : Directionality.maybeOf(context!) ?? TextDirection.ltr;
    return borderRadius.resolve(direction);
  }

  BorderRadius resolvedMediaBorderRadius() {
    final context = mediaContext;
    final direction = context == null
        ? TextDirection.ltr
        : Directionality.maybeOf(context) ?? TextDirection.ltr;
    return (_mediaBorderRadius ?? BorderRadius.zero).resolve(direction);
  }

  Color resolvedSurfaceColor() {
    final currentContext = context;
    return currentContext == null
        ? Colors.transparent
        : Theme.of(currentContext).colorScheme.surface;
  }

  void dispose() {
    _mediaBoundaryKey = null;
    _mediaBorderRadius = null;
    _titleBoundaryKey = null;
    _titleDescriptor = null;
    _lastPointerPosition = null;
    _launchVisibleFraction = null;
  }
}

abstract final class VideoTransitionRegistry {
  static final Map<Object, List<_VideoTransitionSource>> _sources = {};
  static int _nextGeneration = 0;

  static VideoTransitionRegistration register({
    required Object tag,
    required GlobalKey boundaryKey,
    required BuildContext context,
    required BorderRadiusGeometry borderRadius,
    required VideoTransitionSourceLayout layout,
  }) {
    final generation = _nextGeneration++;
    final source = _VideoTransitionSource(
      generation: generation,
      boundaryKey: boundaryKey,
      route: ModalRoute.of(context),
      borderRadius: borderRadius,
      layout: layout,
    );
    (_sources[tag] ??= []).add(source);
    return VideoTransitionRegistration._(tag, generation);
  }

  static VideoTransitionToken? claim({
    required Object tag,
    required String contentKey,
  }) {
    final source = _findLaunchSource(tag);
    final rect = source?.currentRect();
    final mediaRect = source?.currentMediaRect();
    final sourceVisibleRect = source?.currentLaunchVisibleRect();
    if (source == null ||
        rect == null ||
        mediaRect == null ||
        sourceVisibleRect == null ||
        source.route?.isCurrent != true ||
        !_isVisibleRect(rect, sourceVisibleRect) ||
        !_isValidMediaRect(rect, mediaRect)) {
      return null;
    }
    final mediaLaunchBorderRadius = source.resolvedMediaBorderRadius();
    final launchBorderRadius = source.resolvedBorderRadius();
    final title = source.currentTitleSnapshot();
    return VideoTransitionToken(
      tag: tag,
      sourceGeneration: source.generation,
      sourceRoute: source.route,
      launchRect: rect,
      sourceVisibleRect: sourceVisibleRect,
      mediaLaunchRect: mediaRect,
      mediaLaunchBorderRadius: mediaLaunchBorderRadius,
      launchBorderRadius: launchBorderRadius,
      sourceLayout: source.layout,
      sourceSurfaceColor: source.resolvedSurfaceColor(),
      title: title,
      contentKey: contentKey,
    );
  }

  static VideoReturnTarget? resolveReturn(VideoTransitionToken token) {
    final source = _sourceByGeneration(
      token.tag,
      token.sourceGeneration,
    );
    final rect = source?.currentRect();
    final visibleRect = source?.currentVisibleRect();
    final currentMediaRect = source?.currentMediaRect();
    final currentMediaVisibleRect = source?.currentMediaVisibleRect();
    final launchAspectRatio = token.launchRect.width / token.launchRect.height;
    final returnAspectRatio = rect == null ? 0 : rect.width / rect.height;
    final aspectRatioChanged =
        returnAspectRatio <= 0 ||
        (launchAspectRatio - returnAspectRatio).abs() / launchAspectRatio >
            0.08;
    if (source == null ||
        rect == null ||
        visibleRect == null ||
        aspectRatioChanged ||
        !identical(source.route, token.sourceRoute) ||
        source.route?.isActive != true ||
        !_isVisibleRect(rect, visibleRect)) {
      return null;
    }
    final mediaRect =
        currentMediaRect != null && _isValidMediaRect(rect, currentMediaRect)
        ? currentMediaRect
        : null;
    final mediaVisibleRect =
        mediaRect == null || currentMediaVisibleRect == null
        ? null
        : currentMediaVisibleRect.intersect(visibleRect);
    final hasVisibleMediaRect = mediaVisibleRect?.isEmpty == false;
    return VideoReturnTarget(
      rect: rect,
      visibleRect: visibleRect,
      borderRadius: source.resolvedBorderRadius(),
      layout: source.layout,
      mediaRect: hasVisibleMediaRect ? mediaRect : null,
      mediaVisibleRect: hasVisibleMediaRect ? mediaVisibleRect : null,
      mediaBorderRadius: hasVisibleMediaRect
          ? source.resolvedMediaBorderRadius()
          : null,
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
    return _isVisibleRect(rect, visible);
  }

  static bool _isVisibleRect(Rect rect, Rect visible) {
    final visibleRatio =
        (visible.width * visible.height) / (rect.width * rect.height);
    final minimumVisibleWidth = math.min(32.0, rect.width * 0.2);
    final minimumVisibleHeight = math.min(32.0, rect.height * 0.2);
    return visibleRatio >= 0.2 &&
        visible.width >= minimumVisibleWidth &&
        visible.height >= minimumVisibleHeight;
  }

  static bool _isValidMediaRect(Rect sourceRect, Rect mediaRect) {
    if (!mediaRect.left.isFinite ||
        !mediaRect.top.isFinite ||
        !mediaRect.right.isFinite ||
        !mediaRect.bottom.isFinite ||
        mediaRect.width <= 0 ||
        mediaRect.height <= 0) {
      return false;
    }
    final overlap = sourceRect.inflate(2).intersect(mediaRect);
    if (overlap.width <= 0 || overlap.height <= 0) {
      return false;
    }
    final mediaArea = mediaRect.width * mediaRect.height;
    return overlap.width * overlap.height / mediaArea >= 0.85;
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

  static Rect? visiblePortion(BuildContext context, Rect rect) =>
      _visiblePortion(context, rect);

  static Rect _trimSiblingOcclusion(
    BuildContext context,
    Rect sourceRect,
    Rect visibleRect,
    Offset? pointerPosition,
  ) {
    final sourceRenderObject = context.findRenderObject();
    if (pointerPosition == null || sourceRenderObject == null) {
      return visibleRect;
    }
    final anchor = Offset(
      pointerPosition.dx.clamp(visibleRect.left, visibleRect.right),
      pointerPosition.dy.clamp(visibleRect.top, visibleRect.bottom),
    );
    bool receivesHit(Offset position) => _sourceReceivesHit(
      context,
      sourceRenderObject,
      position,
    );
    if (!receivesHit(anchor)) {
      return visibleRect;
    }

    var left = visibleRect.left;
    var top = visibleRect.top;
    var right = visibleRect.right;
    var bottom = visibleRect.bottom;
    const edgeInset = 0.5;
    if (!receivesHit(Offset(anchor.dx, math.min(bottom, top + edgeInset)))) {
      top = _findFirstHit(top, anchor.dy, (value) {
        return receivesHit(Offset(anchor.dx, value));
      });
    }
    if (!receivesHit(Offset(anchor.dx, math.max(top, bottom - edgeInset)))) {
      bottom = _findLastHit(anchor.dy, bottom, (value) {
        return receivesHit(Offset(anchor.dx, value));
      });
    }
    if (!receivesHit(Offset(math.min(right, left + edgeInset), anchor.dy))) {
      left = _findFirstHit(left, anchor.dx, (value) {
        return receivesHit(Offset(value, anchor.dy));
      });
    }
    if (!receivesHit(Offset(math.max(left, right - edgeInset), anchor.dy))) {
      right = _findLastHit(anchor.dx, right, (value) {
        return receivesHit(Offset(value, anchor.dy));
      });
    }
    return Rect.fromLTRB(left, top, right, bottom).intersect(sourceRect);
  }

  static double _findFirstHit(
    double hiddenEdge,
    double visiblePoint,
    bool Function(double) receivesHit,
  ) {
    var low = hiddenEdge;
    var high = visiblePoint;
    for (var index = 0; index < 8; index++) {
      final middle = (low + high) / 2;
      if (receivesHit(middle)) {
        high = middle;
      } else {
        low = middle;
      }
    }
    return high;
  }

  static double _findLastHit(
    double visiblePoint,
    double hiddenEdge,
    bool Function(double) receivesHit,
  ) {
    var low = visiblePoint;
    var high = hiddenEdge;
    for (var index = 0; index < 8; index++) {
      final middle = (low + high) / 2;
      if (receivesHit(middle)) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static bool _sourceReceivesHit(
    BuildContext context,
    RenderObject source,
    Offset position,
  ) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      position,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject) {
        continue;
      }
      RenderObject? current = target;
      while (current != null) {
        if (identical(current, source)) {
          return true;
        }
        current = current.parent;
      }
    }
    return false;
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
    for (final source in sources.reversed) {
      final rect = source.currentRect();
      final mediaRect = source.currentMediaRect();
      if (source.route?.isCurrent == true &&
          rect != null &&
          mediaRect != null &&
          _isVisible(source.context, rect) &&
          _isValidMediaRect(rect, mediaRect)) {
        return source;
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

  static Rect? _currentVisibleRect(Object tag, int generation) =>
      _sourceByGeneration(tag, generation)?.currentVisibleRect();

  static void _notePointerDown(
    Object tag,
    int generation,
    Offset position,
  ) {
    _sourceByGeneration(tag, generation)?.notePointerDown(position);
  }

  static void _attachMedia(
    Object tag,
    int generation,
    GlobalKey boundaryKey,
    BorderRadiusGeometry borderRadius,
  ) {
    _sourceByGeneration(
      tag,
      generation,
    )?.attachMedia(boundaryKey, borderRadius);
  }

  static void _detachMedia(
    Object tag,
    int generation,
    GlobalKey boundaryKey,
  ) {
    _sourceByGeneration(tag, generation)?.detachMedia(boundaryKey);
  }

  static void _attachTitle(
    Object tag,
    int generation,
    GlobalKey boundaryKey,
    VideoTransitionTitleDescriptor descriptor,
  ) {
    _sourceByGeneration(
      tag,
      generation,
    )?.attachTitle(boundaryKey, descriptor);
  }

  static void _detachTitle(
    Object tag,
    int generation,
    GlobalKey boundaryKey,
  ) {
    _sourceByGeneration(tag, generation)?.detachTitle(boundaryKey);
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
    sources.removeAt(index).dispose();
    if (sources.isEmpty) {
      _sources.remove(tag);
    }
  }
}
