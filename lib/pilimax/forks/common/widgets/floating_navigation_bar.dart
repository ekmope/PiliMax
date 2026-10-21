import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass_theme.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
const Duration _kPressDuration = Duration(milliseconds: 130);
const BorderRadius _kBorderRadius = BorderRadius.all(
  Radius.circular(_kNavigationHeight / 2),
);

const Color _softIndicatorDark = Color(0x24FFFFFF);
const Color _softIndicatorLight = Color(0x13000000);
const double _kSoftGlassBlurSigma = 18.0;

/// Floating navigation bar used by the PiliMax main shell.
///
/// The bar supports the regular Material surface and the translucent
/// soft-glass surface.
class FloatingNavigationBar extends StatelessWidget {
  FloatingNavigationBar({
    super.key,
    this.animationDuration = const Duration(milliseconds: 500),
    this.selectedIndex = 0,
    required this.destinations,
    this.onDestinationSelected,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.indicatorColor,
    this.indicatorShape,
    this.labelBehavior,
    this.overlayColor,
    this.labelTextStyle,
    this.labelPadding,
    this.bottomPadding = 8.0,
    this.bottomLift = 0.0,
    this.glassStyle,
    this.liquidGlassStrength = 0.7,
  }) : assert(destinations.length >= 2),
       assert(0 <= selectedIndex && selectedIndex < destinations.length),
       assert(!animationDuration.isNegative),
       assert(elevation == null || elevation >= 0),
       assert(bottomPadding >= 0),
       assert(bottomLift.isFinite && bottomLift >= 0),
       assert(
         liquidGlassStrength.isFinite &&
             liquidGlassStrength >= 0 &&
             liquidGlassStrength <= 1,
       );

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final Color? indicatorColor;
  final ShapeBorder? indicatorShape;
  final NavigationDestinationLabelBehavior? labelBehavior;

  /// Kept for API compatibility; the custom indicator owns all feedback.
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry? labelPadding;
  final double bottomPadding;
  final double bottomLift;
  final GlassStyle? glassStyle;

  /// Optical strength of [GlassStyle.liquid], from 0 (faint) to 1 (full).
  final double liquidGlassStrength;

  @override
  Widget build(BuildContext context) {
    final navigationBarTheme = NavigationBarTheme.of(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final isSoft = glassStyle == GlassStyle.soft;
    final isLiquid = glassStyle == GlassStyle.liquid;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final barWidth = destinations.length * _kIndicatorWidth;
    final effectiveIndicatorColor =
        indicatorColor ??
        (isSoft || isLiquid
            ? (isDark ? _softIndicatorDark : _softIndicatorLight)
            : navigationBarTheme.indicatorColor ??
                  colorScheme.secondaryContainer);
    final effectiveBackground =
        backgroundColor ??
        (isSoft
            ? colorScheme.surfaceContainer.withValues(
                alpha: isDark ? 0.56 : 0.48,
              )
            : navigationBarTheme.backgroundColor ??
                  colorScheme.surfaceContainer);
    final effectiveBorder = isSoft
        ? (isDark ? const Color(0x24FFFFFF) : const Color(0xB8FFFFFF))
        : colorScheme.outlineVariant.withValues(alpha: 0.52);
    final effectiveShadow =
        shadowColor ??
        navigationBarTheme.shadowColor ??
        Colors.black.withValues(alpha: isDark ? 0.28 : 0.14);
    final shellDecoration = BoxDecoration(
      // The soft surface tint is painted inside BackdropFilter. Painting the
      // same opaque-ish color here would tint the backdrop before it can be
      // sampled and make the blur appear ineffective.
      color: isSoft ? Colors.transparent : effectiveBackground,
      borderRadius: _kBorderRadius,
      border: Border.all(color: effectiveBorder),
      boxShadow: [
        BoxShadow(
          color: effectiveShadow,
          blurRadius: isSoft ? (isDark ? 16 : 10) : 12,
          spreadRadius: isSoft ? -2 : 0,
          offset: const Offset(0, 4),
        ),
      ],
    );

    final content = Stack(
      fit: StackFit.expand,
      // The shell background keeps its rounded clip, while the pressed
      // indicator is allowed to reach the rim by a small amount.
      clipBehavior: Clip.none,
      children: [
        if (!isLiquid)
          ClipRRect(
            borderRadius: _kBorderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isSoft)
                  BackdropFilter(
                    key: const ValueKey('softGlassBackdropFilter'),
                    filter: ui.ImageFilter.blur(
                      sigmaX: _kSoftGlassBlurSigma,
                      sigmaY: _kSoftGlassBlurSigma,
                    ),
                    child: ColoredBox(
                      key: const ValueKey('softGlassSurfaceTint'),
                      color: effectiveBackground,
                    ),
                  )
                else
                  ColoredBox(
                    key: const ValueKey('softGlassSurfaceTint'),
                    color: effectiveBackground,
                  ),
              ],
            ),
          ),
        MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _kIndicatorPadding,
            ),
            child: _InteractiveFloatingNavigationBar(
              key: const ValueKey('glassNavigationBar'),
              animationDuration: animationDuration,
              selectedIndex: selectedIndex,
              destinations: destinations,
              onDestinationSelected: onDestinationSelected,
              elevation: elevation ?? 0,
              surfaceTintColor: surfaceTintColor ?? Colors.transparent,
              indicatorColor: effectiveIndicatorColor,
              indicatorShape: indicatorShape,
              labelBehavior: labelBehavior,
              labelTextStyle: labelTextStyle,
              liquid: isLiquid,
              liquidGlassStrength: liquidGlassStrength,
              labelPadding:
                  labelPadding ??
                  navigationBarTheme.labelPadding ??
                  const EdgeInsets.only(top: 2),
            ),
          ),
        ),
      ],
    );

    final bar = isLiquid
        ? LiquidGlass(
            key: const ValueKey('glassVisualShell'),
            style: liquidNavigationBarStyle(colorScheme, liquidGlassStrength),
            shadows: liquidDockShadows(colorScheme),
            child: content,
          )
        : DecoratedBox(
            key: const ValueKey('glassVisualShell'),
            decoration: shellDecoration,
            child: content,
          );

    return Transform.translate(
      offset: Offset(0, -bottomLift),
      child: Align(
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            viewPadding.left,
            0,
            viewPadding.right,
            bottomPadding + viewPadding.bottom,
          ),
          child: SizedBox(
            width: barWidth,
            height: _kNavigationHeight,
            child: bar,
          ),
        ),
      ),
    );
  }
}

/// A soft white light under the icons, lit from the finger and spreading as it
/// fades. It sits below the content so labels keep their contrast.
class _GlassPressGlowPainter extends CustomPainter {
  const _GlassPressGlowPainter({
    required this.center,
    required this.opacity,
    required this.strength,
  });

  final Offset center;
  final double opacity;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final amount = opacity.clamp(0.0, 1.0);
    if (amount <= 0 || strength <= 0) {
      return;
    }
    final reach = 28.0 * (1 + 3 * (1 - amount));
    final alpha = (0.10 * strength * amount).clamp(0.0, 0.10);
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: reach));
    canvas.drawCircle(center, reach, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassPressGlowPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.opacity != opacity ||
        oldDelegate.strength != strength;
  }
}

/// Adds drag and press interactions while leaving the actual destination
/// semantics to Flutter's NavigationBar.
class _InteractiveFloatingNavigationBar extends StatefulWidget {
  const _InteractiveFloatingNavigationBar({
    super.key,
    required this.animationDuration,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.elevation,
    required this.surfaceTintColor,
    required this.indicatorColor,
    required this.indicatorShape,
    required this.labelBehavior,
    required this.labelTextStyle,
    required this.labelPadding,
    required this.liquid,
    required this.liquidGlassStrength,
  });

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final double elevation;
  final Color surfaceTintColor;
  final Color indicatorColor;
  final ShapeBorder? indicatorShape;
  final NavigationDestinationLabelBehavior? labelBehavior;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry labelPadding;
  final bool liquid;
  final double liquidGlassStrength;

  @override
  State<_InteractiveFloatingNavigationBar> createState() =>
      _InteractiveFloatingNavigationBarState();
}

class _InteractiveFloatingNavigationBarState
    extends State<_InteractiveFloatingNavigationBar>
    with TickerProviderStateMixin {
  late final AnimationController _selectionController;
  late final AnimationController _pressController;
  late final AnimationController _glowController;
  late final Listenable _interactionListenable;
  Offset? _glowAt;
  late double _fromIndex;
  late double _targetIndex;
  double? _dragIndex;
  double _itemExtent = _kIndicatorWidth;
  bool _isPressed = false;
  bool _interactionCommitted = false;
  int? _activePointer;
  int? _pendingPointerUp;
  Offset _pointerDownPosition = Offset.zero;
  Offset _lastPointerPosition = Offset.zero;
  Duration _lastPointerTime = Duration.zero;
  bool _gestureDirectionLocked = false;
  bool _isVerticalGesture = false;
  double _dragVelocity = 0;
  TextDirection _textDirection = TextDirection.ltr;

  double get _animatedIndex =>
      _fromIndex + (_targetIndex - _fromIndex) * _selectionController.value;

  bool get _isRtl => _textDirection == TextDirection.rtl;

  double get _directionSign => _isRtl ? -1 : 1;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex.toDouble();
    _targetIndex = _fromIndex;
    _selectionController = AnimationController(vsync: this, value: 1);
    _pressController = AnimationController(
      vsync: this,
      duration: _kPressDuration,
      reverseDuration: const Duration(milliseconds: 180),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 500),
    );
    _interactionListenable = Listenable.merge([
      _selectionController,
      _pressController,
      _glowController,
    ]);
  }

  @override
  void didUpdateWidget(_InteractiveFloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != widget.destinations.length) {
      final maxIndex = (widget.destinations.length - 1).toDouble();
      _fromIndex = _fromIndex.clamp(0, maxIndex).toDouble();
      _targetIndex = _targetIndex.clamp(0, maxIndex).toDouble();
      _dragIndex = _dragIndex?.clamp(0, maxIndex).toDouble();
    }
    if (_targetIndex != widget.selectedIndex.toDouble()) {
      _animateTo(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _pressController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _animateTo(double index, {double velocity = 0}) {
    final currentIndex = _dragIndex ?? _animatedIndex;
    _selectionController.stop();
    _fromIndex = currentIndex;
    _targetIndex = index;
    _dragIndex = null;
    _gestureDirectionLocked = false;
    _isVerticalGesture = false;
    _dragVelocity = 0;
    _isPressed = false;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _pressController.value = 0;
      _selectionController.value = 1;
      return;
    }
    _pressController.reverse();
    _selectionController.value = 0;
    _selectionController.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          ratio: 0.82,
          stiffness: 420,
          mass: 1,
        ),
        0,
        1,
        velocity.clamp(-3.0, 3.0).toDouble(),
        snapToEnd: true,
      ),
    );
    if (mounted) setState(() {});
  }

  void _handleDestinationSelected(int index) {
    if (_interactionCommitted) return;
    _interactionCommitted = true;
    if (widget.liquid && index != widget.selectedIndex) {
      HapticFeedback.selectionClick();
    }
    _animateTo(index.toDouble());
    widget.onDestinationSelected?.call(index);
    if (_activePointer == null && _pendingPointerUp == null) {
      _scheduleInteractionReset();
    }
  }

  void _scheduleInteractionReset() {
    Future<void>.microtask(() {
      if (mounted && _activePointer == null) {
        _interactionCommitted = false;
      }
    });
  }

  double _indexForX(double x) {
    final logicalX = _isRtl ? _itemExtent * widget.destinations.length - x : x;
    return (logicalX / _itemExtent - 0.5)
        .clamp(0.0, (widget.destinations.length - 1).toDouble())
        .toDouble();
  }

  void _fadeGlow() {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _glowController.value = 0;
    } else {
      _glowController.reverse();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _selectionController.stop();
    _activePointer = event.pointer;
    _pendingPointerUp = null;
    _pointerDownPosition = event.localPosition;
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    _gestureDirectionLocked = false;
    _isVerticalGesture = false;
    _dragVelocity = 0;
    _interactionCommitted = false;
    if (widget.liquid) {
      _glowAt = event.localPosition;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _glowController.value = 1;
      } else {
        _glowController.forward(from: 0);
      }
    }
    setState(() => _isPressed = true);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _pressController.value = 1;
    } else {
      _pressController.forward();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final delta = event.localPosition - _pointerDownPosition;
    if (!_gestureDirectionLocked && delta.distance > kTouchSlop) {
      _gestureDirectionLocked = true;
      _isVerticalGesture = delta.dy.abs() > delta.dx.abs();
      if (_isVerticalGesture) {
        _fadeGlow();
        _animateTo(widget.selectedIndex.toDouble());
        return;
      }
    }
    if (_isVerticalGesture) return;

    if (widget.liquid) {
      _glowAt = event.localPosition;
      if (_glowController.value > 0) {
        setState(() {});
      }
    }

    final elapsed = (event.timeStamp - _lastPointerTime).inMicroseconds;
    final deltaX = event.localPosition.dx - _lastPointerPosition.dx;
    final instantaneousVelocity = elapsed > 0
        ? (deltaX * _directionSign / elapsed * 1000000 / _itemExtent)
              .clamp(-3.0, 3.0)
              .toDouble()
        : 0.0;
    _dragVelocity = (_dragVelocity * 0.82 + instantaneousVelocity * 0.18)
        .clamp(-3.0, 3.0)
        .toDouble();
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    final nextIndex = _indexForX(event.localPosition.dx);
    final previousIndex = _dragIndex;
    if (previousIndex != null &&
        widget.liquid &&
        nextIndex.round() != previousIndex.round()) {
      HapticFeedback.selectionClick();
    }
    if (_dragIndex == null || (nextIndex - _dragIndex!).abs() > 0.001) {
      setState(() => _dragIndex = nextIndex);
    }
  }

  double _pointerVelocity(PointerUpEvent event) {
    final elapsed = (event.timeStamp - _lastPointerTime).inMicroseconds;
    if (elapsed <= 0) return _dragVelocity;
    return ((event.localPosition.dx - _lastPointerPosition.dx) *
            _directionSign /
            elapsed *
            1000000 /
            _itemExtent)
        .clamp(-3.0, 3.0)
        .toDouble();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final dragIndex = _dragIndex ?? _indexForX(event.localPosition.dx);
    final velocity = _pointerVelocity(event);
    _activePointer = null;
    _pendingPointerUp = event.pointer;
    _fadeGlow();
    Future<void>.microtask(() {
      if (!mounted || _pendingPointerUp != event.pointer) return;
      _pendingPointerUp = null;
      if (_interactionCommitted) {
        _scheduleInteractionReset();
        return;
      }
      _interactionCommitted = true;
      if (_isVerticalGesture || !_gestureDirectionLocked) {
        _animateTo(widget.selectedIndex.toDouble());
        _scheduleInteractionReset();
        return;
      }
      final nearest = (dragIndex + velocity * 0.08)
          .round()
          .clamp(0, widget.destinations.length - 1)
          .toInt();
      final targetIndex = _nearestEnabledIndex(nearest);
      if (targetIndex == null) {
        _animateTo(widget.selectedIndex.toDouble());
      } else {
        _animateTo(targetIndex.toDouble(), velocity: velocity);
        if (targetIndex != widget.selectedIndex) {
          widget.onDestinationSelected?.call(targetIndex);
        }
      }
      _scheduleInteractionReset();
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pendingPointerUp = null;
    _interactionCommitted = true;
    _fadeGlow();
    _animateTo(widget.selectedIndex.toDouble());
    _scheduleInteractionReset();
  }

  bool _destinationEnabled(int index) {
    final destination = widget.destinations[index];
    if (destination is FloatingNavigationDestination) {
      return destination.enabled;
    }
    if (destination is NavigationDestination) return destination.enabled;
    return true;
  }

  int? _nearestEnabledIndex(int index) {
    final maxIndex = widget.destinations.length - 1;
    final clamped = index.clamp(0, maxIndex).toInt();
    if (_destinationEnabled(clamped)) return clamped;
    for (var distance = 1; distance <= maxIndex; distance++) {
      final left = clamped - distance;
      if (left >= 0 && _destinationEnabled(left)) return left;
      final right = clamped + distance;
      if (right <= maxIndex && _destinationEnabled(right)) return right;
    }
    return null;
  }

  Rect _lensRect() {
    final progress = math.max(
      _pressController.value,
      _isPressed ? 0.2 : 0.0,
    );
    final visualIndex = _dragIndex ?? _animatedIndex;
    final logicalCenter = (visualIndex + 0.5) * _itemExtent;
    final center = _isRtl
        ? _itemExtent * widget.destinations.length - logicalCenter
        : logicalCenter;
    final jelly = widget.liquid
        ? 0.06 * (_dragVelocity.abs() / 3).clamp(0.0, 1.0)
        : 0.0;
    final width = _kIndicatorWidth * (1 + 0.08 * progress + jelly);
    final lift = widget.liquid ? 2.0 * progress : 0.0;
    final height =
        _kNavigationHeight -
        2 * _kIndicatorPadding +
        4 * progress +
        (widget.liquid ? 4 * progress : 0);
    final top = (_kNavigationHeight - height) / 2 - lift;
    return Rect.fromLTWH(center - width / 2, top, width, height);
  }

  Widget _buildIndicator(Rect rect) {
    final shape =
        widget.indicatorShape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rect.height / 2),
        );
    if (widget.liquid) {
      final colorScheme = Theme.of(context).colorScheme;
      return Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A faint plate keeps the selected destination legible when
              // the shader filter is unavailable; when it is available the
              // glass lens paints the same shape over it.
              DecoratedBox(
                key: const ValueKey('floatingNavigationIndicator'),
                decoration: ShapeDecoration(
                  color: widget.indicatorColor,
                  shape: shape,
                ),
              ),
              LiquidGlass(
                key: const ValueKey('liquidGlassLens'),
                style: liquidNavigationLensStyle(
                  colorScheme,
                  widget.liquidGlassStrength,
                ),
                child: const SizedBox.expand(),
              ),
            ],
          ),
        ),
      );
    }
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          key: const ValueKey('floatingNavigationIndicator'),
          decoration: ShapeDecoration(
            color: widget.indicatorColor,
            shape: shape,
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationBar({required bool duplicate}) {
    return NavigationBar(
      key: duplicate ? null : const ValueKey('floatingNavigationSemanticsBar'),
      animationDuration: Duration.zero,
      selectedIndex: widget.selectedIndex,
      destinations: widget.destinations,
      onDestinationSelected: duplicate
          ? _ignoreDestination
          : _handleDestinationSelected,
      backgroundColor: Colors.transparent,
      elevation: widget.elevation,
      shadowColor: Colors.transparent,
      surfaceTintColor: widget.surfaceTintColor,
      indicatorColor: Colors.transparent,
      indicatorShape: widget.indicatorShape,
      height: _kNavigationHeight,
      labelBehavior: widget.labelBehavior,
      // The custom indicator is the only interaction surface. Disable
      // Material's pressed, hover, and focus overlay so it cannot paint a
      // second mask over the icon.
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      labelTextStyle: widget.labelTextStyle,
      labelPadding: widget.labelPadding,
    );
  }

  void _ignoreDestination(int index) {}

  Matrix4 _lensContentTransform(Rect rect) {
    final progress = math.max(
      _pressController.value,
      _isPressed ? 0.2 : 0.0,
    );
    final scale = 1 + 0.16 * progress;
    final center = rect.center;
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  bool get _showLensContent {
    return widget.liquid &&
        (_isPressed ||
            _pressController.value > 0.001 ||
            _dragIndex != null ||
            _selectionController.isAnimating);
  }

  @override
  Widget build(BuildContext context) {
    _textDirection = Directionality.of(context);
    final realBar = MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      removeTop: true,
      removeRight: true,
      removeBottom: true,
      child: _buildNavigationBar(duplicate: false),
    );
    final duplicateBar = widget.liquid
        ? MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            removeTop: true,
            removeRight: true,
            removeBottom: true,
            child: _buildNavigationBar(duplicate: true),
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : widget.destinations.length * _kIndicatorWidth;
        _itemExtent = width / widget.destinations.length;
        return AnimatedBuilder(
          animation: _interactionListenable,
          builder: (context, _) {
            final lens = _lensRect();
            final showLensContent = _showLensContent;
            final colorScheme = Theme.of(context).colorScheme;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  _buildIndicator(lens),
                  if (widget.liquid && _glowAt != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRRect(
                          borderRadius: _kBorderRadius,
                          child: CustomPaint(
                            painter: _GlassPressGlowPainter(
                              center: _glowAt!,
                              opacity: _glowController.value,
                              strength: widget.liquidGlassStrength,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Paint the real bar's content only outside the lens. This
                  // is a paint-only clip: hit testing, focus and semantics stay
                  // on the real NavigationBar. Non-liquid styles keep the
                  // original tree without the clip.
                  if (widget.liquid)
                    _PaintClipPath(
                      clipper: _LensClip(
                        rect: lens,
                        outside: true,
                        enabled: showLensContent,
                      ),
                      child: realBar,
                    )
                  else
                    realBar,
                  // Inside the lens, draw a second, magnified and tinted copy.
                  // It is inert and excluded from semantics/focus; the real bar
                  // still owns the interaction.
                  if (showLensContent && duplicateBar != null)
                    Positioned.fill(
                      key: const ValueKey('liquidGlassLensContent'),
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: ExcludeFocus(
                            child: _PaintClipPath(
                              clipper: _LensClip(
                                rect: lens,
                                outside: false,
                                enabled: true,
                              ),
                              child: Transform(
                                transform: _lensContentTransform(lens),
                                filterQuality: FilterQuality.high,
                                child: ColorFiltered(
                                  colorFilter: ui.ColorFilter.mode(
                                    colorScheme.primary,
                                    ui.BlendMode.srcATop,
                                  ),
                                  child: duplicateBar,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Clips paint (not hit testing) to a moving lens.
class _LensClip extends CustomClipper<Path> {
  const _LensClip({
    required this.rect,
    required this.outside,
    required this.enabled,
  });

  final Rect rect;
  final bool outside;
  final bool enabled;

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Offset.zero & size);
    if (!enabled) {
      return full;
    }
    final lens = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      );
    if (!outside) {
      return lens;
    }
    return Path.combine(ui.PathOperation.difference, full, lens);
  }

  @override
  bool shouldReclip(_LensClip oldClipper) {
    return oldClipper.rect != rect ||
        oldClipper.outside != outside ||
        oldClipper.enabled != enabled;
  }
}

/// Applies [clipper] while painting but leaves hit testing and semantics on
/// the child, so clipping the real navigation bar cannot eat taps under the
/// magnified lens.
class _PaintClipPath extends SingleChildRenderObjectWidget {
  const _PaintClipPath({required this.clipper, super.child});

  final CustomClipper<Path> clipper;

  @override
  _RenderPaintClipPath createRenderObject(BuildContext context) {
    return _RenderPaintClipPath(clipper);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintClipPath renderObject,
  ) {
    renderObject.clipper = clipper;
  }
}

class _RenderPaintClipPath extends RenderProxyBox {
  _RenderPaintClipPath(this._clipper);

  CustomClipper<Path> _clipper;

  set clipper(CustomClipper<Path> value) {
    if (identical(value, _clipper)) {
      return;
    }
    _clipper = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipPath(
      needsCompositing,
      offset,
      (Offset.zero & size).inflate(8),
      _clipper.getClip(size),
      (context, offset) => super.paint(context, offset),
    );
  }
}

/// A destination that can wrap its icon, for example to add an unread badge.
class FloatingNavigationDestination extends StatelessWidget {
  const FloatingNavigationDestination({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
    this.enabled = true,
    this.iconWrapper,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;
  final bool enabled;
  final Widget Function(Widget icon)? iconWrapper;

  @override
  Widget build(BuildContext context) {
    final wrappedIcon = iconWrapper?.call(icon) ?? icon;
    final wrappedSelectedIcon = selectedIcon == null
        ? null
        : iconWrapper?.call(selectedIcon!) ?? selectedIcon;
    return NavigationDestination(
      icon: wrappedIcon,
      selectedIcon: wrappedSelectedIcon,
      label: label,
      tooltip: tooltip,
      enabled: enabled,
    );
  }
}
