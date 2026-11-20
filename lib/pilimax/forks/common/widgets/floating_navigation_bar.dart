import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass_theme.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show VelocityTracker, computeHitSlop, kPrimaryButton;
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
const Duration _kPressDuration = Duration(milliseconds: 130);
// Lens lift and fling projection follow Prism UI navigation_dock.dart
// at 6c47901cc80b5325bdb9650579ca2e000a60b39e.
const int _kFlingProjectionMs = 100;
const double _kLiftReleaseDistance = 0.04;
const _kSelectionSpring = SpringDescription(
  mass: 1,
  stiffness: 420,
  damping: 36,
);
const BorderRadius _kBorderRadius = BorderRadius.all(
  Radius.circular(_kNavigationHeight / 2),
);

const Color _softIndicatorDark = Color(0x24FFFFFF);
const Color _softIndicatorLight = Color(0x13000000);
const double _kSoftGlassBlurSigma = 18.0;

/// Floating navigation bar used by the PiliMax main shell.
///
/// The bar supports Material, soft glass and liquid glass surfaces.
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

  /// Overrides the keyboard focus and pointer hover overlays.
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
        (isLiquid
            ? liquidNavigationSelectionColor(colorScheme)
            : isSoft
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

    final background = isLiquid
        ? null
        : ClipRRect(
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
          );

    final bar = _InteractiveFloatingNavigationBar(
      key: const ValueKey('glassNavigationBar'),
      animationDuration: animationDuration,
      selectedIndex: selectedIndex,
      destinations: destinations,
      onDestinationSelected: onDestinationSelected,
      elevation: elevation ?? 0,
      surfaceTintColor: surfaceTintColor ?? Colors.transparent,
      indicatorColor: effectiveIndicatorColor,
      indicatorShape: indicatorShape,
      overlayColor: overlayColor,
      labelBehavior: labelBehavior,
      labelTextStyle: labelTextStyle,
      liquid: isLiquid,
      liquidGlassStrength: liquidGlassStrength,
      labelPadding:
          labelPadding ??
          navigationBarTheme.labelPadding ??
          const EdgeInsets.only(top: 2),
      shellDecoration: shellDecoration,
      background: background,
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
            child: RepaintBoundary(child: bar),
          ),
        ),
      ),
    );
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
    required this.overlayColor,
    required this.labelBehavior,
    required this.labelTextStyle,
    required this.labelPadding,
    required this.liquid,
    required this.liquidGlassStrength,
    required this.shellDecoration,
    required this.background,
  });

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final double elevation;
  final Color surfaceTintColor;
  final Color indicatorColor;
  final ShapeBorder? indicatorShape;
  final WidgetStateProperty<Color?>? overlayColor;
  final NavigationDestinationLabelBehavior? labelBehavior;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry labelPadding;
  final bool liquid;
  final double liquidGlassStrength;
  final BoxDecoration shellDecoration;
  final Widget? background;

  @override
  State<_InteractiveFloatingNavigationBar> createState() =>
      _InteractiveFloatingNavigationBarState();
}

enum _DockGesture { pending, horizontal, verticalCanceled }

class _InteractiveFloatingNavigationBarState
    extends State<_InteractiveFloatingNavigationBar>
    with TickerProviderStateMixin {
  late final AnimationController _selectionController;
  late final AnimationController _pressController;
  late final AnimationController _glowController;
  late final Listenable _lensMotion;
  final _drag = ValueNotifier<({double index, double stretch})?>(null);
  final _glow = ValueNotifier(LiquidGlassGlow.none);
  Offset _glowAt = Offset.zero;
  late double _selectionTarget;
  double _itemExtent = _kIndicatorWidth;
  TextDirection _textDirection = TextDirection.ltr;
  bool _reduceMotion = false;
  bool _dropAfterLift = false;
  int? _activePointer;
  Object? _pendingPointerUp;
  Offset _pointerDownPosition = Offset.zero;
  _DockGesture _gesture = _DockGesture.pending;
  double _gestureSlop = 0;
  VelocityTracker? _velocityTracker;

  double get _lastIndex => (widget.destinations.length - 1).toDouble();
  double get _directionSign => _textDirection == TextDirection.rtl ? -1 : 1;

  @override
  void initState() {
    super.initState();
    _selectionTarget = widget.selectedIndex.toDouble();
    _selectionController = AnimationController.unbounded(
      vsync: this,
      value: _selectionTarget,
    )..addListener(_dropLiftWhenReady);
    _pressController = AnimationController(
      vsync: this,
      duration: _kPressDuration,
      reverseDuration: const Duration(milliseconds: 180),
    )..addListener(_dropLiftWhenReady);
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 300),
    )..addListener(_updateGlow);
    _lensMotion = Listenable.merge([
      _selectionController,
      _pressController,
      _drag,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _dropAfterLift = false;
      _pressController.value = 0;
      _glowController.value = 0;
      _selectionController.value = _selectionTarget;
    }
  }

  @override
  void didUpdateWidget(_InteractiveFloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != widget.destinations.length) {
      _drag.value = null;
      _selectionController.value = _selectionController.value.clamp(
        0,
        _lastIndex,
      );
    }
    if (_activePointer == null &&
        (oldWidget.selectedIndex != widget.selectedIndex ||
            oldWidget.destinations.length != widget.destinations.length)) {
      _settleSelection(widget.selectedIndex);
    }
    if (oldWidget.liquidGlassStrength != widget.liquidGlassStrength) {
      _updateGlow();
    }
    if (oldWidget.liquid && !widget.liquid) {
      _dropAfterLift = false;
      _pressController.value = 0;
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _pressController.dispose();
    _glowController.dispose();
    _drag.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _settleSelection(int index, {double? velocity}) {
    final drag = _drag.value;
    final current = drag?.index ?? _selectionController.value;
    final physicalVelocity = velocity ?? _selectionController.velocity;
    if (drag == null &&
        _selectionTarget == index &&
        (_selectionController.isAnimating || current == index)) {
      return;
    }
    _selectionTarget = index.toDouble();
    _drag.value = null;
    if (_reduceMotion || current == index) {
      _selectionController.value = _selectionTarget;
      _dropLiftWhenReady();
      return;
    }
    _selectionController.animateWith(
      SpringSimulation(
        _kSelectionSpring,
        current,
        _selectionTarget,
        physicalVelocity.clamp(-16.0, 16.0),
        snapToEnd: true,
      ),
    );
  }

  void _dropLiftWhenReady() {
    if (!_dropAfterLift ||
        _pressController.value < 1 ||
        (_selectionController.value - _selectionTarget).abs() >
            _kLiftReleaseDistance) {
      return;
    }
    _dropAfterLift = false;
    _pressController.reverse();
  }

  void _releasePress({required bool finishLift}) {
    if (finishLift && widget.liquid && !_reduceMotion) {
      _dropAfterLift = true;
      _dropLiftWhenReady();
    } else {
      _dropAfterLift = false;
      if (_reduceMotion) {
        _pressController.value = 0;
      } else {
        _pressController.reverse();
      }
    }
  }

  void _updateGlow() {
    final amount = _glowController.value;
    _glow.value = amount == 0
        ? LiquidGlassGlow.none
        : LiquidGlassGlow(
            center: _glowAt + const Offset(_kIndicatorPadding, 0),
            reach: 28 * (1 + 3 * (1 - amount)),
            strength: 0.06 * widget.liquidGlassStrength * amount * amount,
            wash: 0.7,
          );
  }

  void _fadeGlow() {
    if (_reduceMotion) {
      _glowController.value = 0;
    } else {
      _glowController.reverse();
    }
  }

  // Flutter's real destinations own the keyboard and semantics actions. The
  // pointer listener handles touch/mouse once, including taps where another
  // recognizer preempts Material's tap.
  void _handleDestinationSelected(int index) {
    if (_activePointer != null || _pendingPointerUp != null) return;
    _settleSelection(index);
    widget.onDestinationSelected?.call(index);
  }

  double _indexForX(double x) {
    final width = _itemExtent * widget.destinations.length;
    final logicalX = _directionSign < 0 ? width - x : x;
    return (logicalX / _itemExtent - 0.5).clamp(0, _lastIndex);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null || event.buttons & kPrimaryButton == 0) return;
    _activePointer = event.pointer;
    _pendingPointerUp = null;
    _pointerDownPosition = event.localPosition;
    _gesture = _DockGesture.pending;
    _gestureSlop = computeHitSlop(
      event.kind,
      MediaQuery.gestureSettingsOf(context),
    );
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _dropAfterLift = false;
    if (widget.liquid) {
      final index = _indexForX(event.localPosition.dx).round();
      if (!_destinationEnabled(index)) return;
      _settleSelection(index);
      _glowAt = event.localPosition;
      if (_reduceMotion) {
        _glowController.value = 1;
      } else {
        _glowController.forward();
      }
      _updateGlow();
    }
    if (!_reduceMotion) _pressController.forward();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer ||
        _gesture == _DockGesture.verticalCanceled) {
      return;
    }
    _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    final delta = event.localPosition - _pointerDownPosition;
    if (_gesture == _DockGesture.pending && delta.distance > _gestureSlop) {
      if (delta.dy.abs() > delta.dx.abs()) {
        _gesture = _DockGesture.verticalCanceled;
        _settleSelection(widget.selectedIndex);
        _releasePress(finishLift: false);
        _fadeGlow();
        return;
      }
      _gesture = _DockGesture.horizontal;
      if (!_reduceMotion) _pressController.forward();
      if (widget.liquid && !_reduceMotion) _glowController.forward();
    }
    if (widget.liquid) {
      _glowAt = event.localPosition;
      _updateGlow();
    }
    if (_gesture == _DockGesture.horizontal) {
      final width = _itemExtent * widget.destinations.length;
      final x = event.localPosition.dx;
      final overrun = x - x.clamp(0, width);
      final stretch = widget.liquid && !_reduceMotion
          ? 8 * overrun / (24 + overrun.abs())
          : 0.0;
      _selectionController.stop();
      _drag.value = (index: _indexForX(x), stretch: stretch);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final phase = _gesture;
    final down = _pointerDownPosition;
    final drag = _drag.value;
    final velocity =
        (_velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0) *
        _directionSign /
        _itemExtent;
    _activePointer = null;
    _velocityTracker = null;
    final pending = _pendingPointerUp = Object();
    _fadeGlow();
    // Finish dispatch before routing. Material's tap is ignored while this
    // release is pending, so the selected callback fires once.
    Future<void>.microtask(() {
      if (!mounted || !identical(_pendingPointerUp, pending)) return;
      _pendingPointerUp = null;
      if (phase == _DockGesture.verticalCanceled) {
        _settleSelection(widget.selectedIndex);
        return;
      }
      if (phase == _DockGesture.pending) {
        final index = _indexForX(down.dx).round();
        final withinSlop =
            (event.localPosition - down).distance <= _gestureSlop;
        if (withinSlop && _destinationEnabled(index)) {
          _settleSelection(index);
          _releasePress(finishLift: true);
          widget.onDestinationSelected?.call(index);
        } else {
          _settleSelection(widget.selectedIndex);
          _releasePress(finishLift: false);
        }
        return;
      }
      final position = drag?.index ?? _indexForX(event.localPosition.dx);
      final target = _projectDragTarget(position, velocity);
      _settleSelection(target ?? widget.selectedIndex, velocity: velocity);
      _releasePress(finishLift: target != null);
      if (target != null && target != widget.selectedIndex) {
        widget.onDestinationSelected?.call(target);
      }
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _velocityTracker = null;
    final pending = _pendingPointerUp = Object();
    _settleSelection(widget.selectedIndex);
    _releasePress(finishLift: false);
    _fadeGlow();
    Future<void>.microtask(() {
      if (identical(_pendingPointerUp, pending)) _pendingPointerUp = null;
    });
  }

  bool _destinationEnabled(int index) {
    final destination = widget.destinations[index];
    if (destination is FloatingNavigationDestination) {
      return destination.enabled;
    }
    if (destination is NavigationDestination) return destination.enabled;
    return true;
  }

  int? _nearestEnabledIndex(double position) {
    int? nearest;
    var shortestDistance = double.infinity;
    for (var index = 0; index < widget.destinations.length; index++) {
      final distance = (index - position).abs();
      if (distance < shortestDistance && _destinationEnabled(index)) {
        nearest = index;
        shortestDistance = distance;
      }
    }
    return nearest;
  }

  int? _projectDragTarget(double position, double velocity) {
    final nearest = _nearestEnabledIndex(position);
    if (nearest == null || velocity == 0) return nearest;
    final projected = position + velocity * _kFlingProjectionMs / 1000;
    final step = velocity > 0 ? 1 : -1;
    for (
      var index = nearest + step;
      index >= 0 && index < widget.destinations.length;
      index += step
    ) {
      if (_destinationEnabled(index)) {
        return (index - projected).abs() < (nearest - projected).abs()
            ? index
            : nearest;
      }
    }
    return nearest;
  }

  Rect _lensRect(double progress) {
    final drag = _drag.value;
    final index =
        drag?.index ?? _selectionController.value.clamp(0, _lastIndex);
    final logicalCenter = (index + 0.5) * _itemExtent;
    final center = _directionSign < 0
        ? _itemExtent * widget.destinations.length - logicalCenter
        : logicalCenter;
    final stretch = drag?.stretch ?? 0;
    final jelly = widget.liquid && !_reduceMotion && drag == null
        ? 0.04 * (_selectionController.velocity.abs() / 8).clamp(0.0, 1.0)
        : 0.0;
    final width =
        math.min(_kIndicatorWidth, _itemExtent + _kIndicatorPadding) *
            (1 + (widget.liquid ? 0.065 : 0.08) * progress + jelly) +
        stretch.abs() / 2;
    final height =
        _kNavigationHeight -
        2 * _kIndicatorPadding +
        (widget.liquid ? 12 : 4) * progress;
    return Rect.fromCenter(
      center: Offset(center + stretch, _kNavigationHeight / 2),
      width: width,
      height: height,
    );
  }

  Rect _lensCaptureHold(Rect pane) {
    final width = _itemExtent * widget.destinations.length;
    final anchor = _drag.value?.index.roundToDouble() ?? _selectionTarget;
    final logicalCenter = (anchor + 0.5) * _itemExtent;
    final center = _directionSign < 0 ? width - logicalCenter : logicalCenter;
    return Rect.fromLTRB(
      math.max(-_kIndicatorPadding, center - _itemExtent),
      -2,
      math.min(width + _kIndicatorPadding, center + _itemExtent),
      _kNavigationHeight + 2,
    ).shift(-pane.topLeft);
  }

  Widget _buildIndicator(
    Rect rect, {
    required double lift,
    required LiquidGlassStyle? lensStyle,
    required bool shaderSupported,
  }) {
    final shape =
        widget.indicatorShape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rect.height / 2),
        );
    final color = widget.indicatorColor;
    final fill = widget.liquid
        ? color.withValues(
            alpha: color.a * (1 - (shaderSupported ? 1 : 0.65) * lift),
          )
        : color;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              key: const ValueKey('floatingNavigationIndicator'),
              decoration: ShapeDecoration(color: fill, shape: shape),
            ),
            if (lensStyle != null && lift > 0)
              LiquidGlass(
                key: const ValueKey('liquidGlassLens'),
                style: lensStyle.scale(lift),
                hold: shaderSupported ? _lensCaptureHold(rect) : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationBar({
    required int selectedIndex,
    required bool duplicate,
    required ColorScheme colorScheme,
  }) {
    return NavigationBar(
      key: duplicate ? null : const ValueKey('floatingNavigationSemanticsBar'),
      selectedIndex: selectedIndex,
      destinations: widget.destinations,
      onDestinationSelected: !duplicate && widget.onDestinationSelected != null
          ? _handleDestinationSelected
          : null,
      backgroundColor: Colors.transparent,
      elevation: widget.elevation,
      shadowColor: Colors.transparent,
      surfaceTintColor: widget.surfaceTintColor,
      indicatorColor: Colors.transparent,
      indicatorShape: widget.indicatorShape,
      height: _kNavigationHeight,
      labelBehavior: widget.labelBehavior,
      overlayColor: duplicate
          ? const WidgetStatePropertyAll(Colors.transparent)
          : widget.overlayColor ??
                WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.focused)) {
                    return colorScheme.onSurface.withValues(alpha: 0.16);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return colorScheme.onSurface.withValues(alpha: 0.07);
                  }
                  return Colors.transparent;
                }),
      labelTextStyle: widget.labelTextStyle,
      labelPadding: widget.labelPadding,
      animationDuration: widget.liquid || _reduceMotion
          ? Duration.zero
          : widget.animationDuration,
    );
  }

  Widget _lensContent({
    required Rect lens,
    required Widget content,
    required LiquidGlassStyle? contentStyle,
  }) {
    return Positioned.fill(
      key: const ValueKey('liquidGlassLensContent'),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ExcludeFocus(
            child: ClipPath(
              clipper: _LensClip(rect: lens, outside: false),
              // Offscreen clipping lets this pane sample just the destination
              // paint underneath it, independent of the shell and page.
              clipBehavior: contentStyle == null
                  ? Clip.antiAlias
                  : Clip.antiAliasWithSaveLayer,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  content,
                  if (contentStyle != null)
                    Positioned.fromRect(
                      rect: lens,
                      child: LiquidGlass(
                        key: const ValueKey('liquidGlassLensWarp'),
                        style: contentStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _textDirection = Directionality.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final realBar = RepaintBoundary(
      child: _buildNavigationBar(
        selectedIndex: widget.selectedIndex,
        duplicate: false,
        colorScheme: colorScheme,
      ),
    );
    final shaderSupported = ui.ImageFilter.isShaderFilterSupported;
    final lensStyle = widget.liquid
        ? liquidNavigationLensStyle(colorScheme, widget.liquidGlassStrength)
        : null;
    final warpContent =
        widget.liquid &&
        shaderSupported &&
        LiquidGlassScope.qualityOf(context) == LiquidGlassQuality.ultra;
    final contentStyle = warpContent
        ? liquidNavigationLensContentStyle(
            colorScheme,
            widget.liquidGlassStrength,
          )
        : null;

    final content = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        ?widget.background,
        if (widget.liquid && !shaderSupported)
          IgnorePointer(
            child: ClipRRect(
              borderRadius: _kBorderRadius,
              child: CustomPaint(painter: _FrostedDockGlow(_glow)),
            ),
          ),
        MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kIndicatorPadding),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _itemExtent =
                      constraints.maxWidth / widget.destinations.length;
                  int? paintedIndex;
                  Widget? visualBar;
                  return AnimatedBuilder(
                    animation: _lensMotion,
                    builder: (context, _) {
                      final lift = _reduceMotion ? 0.0 : _pressController.value;
                      final lens = _lensRect(lift);
                      final showLensContent = widget.liquid && lift > 0;
                      if (showLensContent) {
                        final index =
                            _nearestEnabledIndex(
                              _drag.value?.index ?? _selectionTarget,
                            ) ??
                            widget.selectedIndex;
                        if (index != paintedIndex) {
                          paintedIndex = index;
                          visualBar = _buildNavigationBar(
                            selectedIndex: index,
                            duplicate: true,
                            colorScheme: colorScheme,
                          );
                        }
                      }
                      return Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          _buildIndicator(
                            lens,
                            lift: lift,
                            lensStyle: lensStyle,
                            shaderSupported: shaderSupported,
                          ),
                          // The same destination render objects keep focus and
                          // hit-testing as their paint is clipped during lift.
                          if (widget.liquid)
                            _PaintClipPath(
                              clipper: showLensContent
                                  ? _LensClip(rect: lens, outside: true)
                                  : null,
                              child: realBar,
                            )
                          else
                            realBar,
                          if (showLensContent)
                            _lensContent(
                              lens: lens,
                              content: visualBar!,
                              contentStyle: contentStyle?.scale(lift),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
    const shellKey = ValueKey('glassVisualShell');
    if (!widget.liquid) {
      return DecoratedBox(
        key: shellKey,
        decoration: widget.shellDecoration,
        child: content,
      );
    }
    final style = liquidNavigationBarStyle(
      colorScheme,
      widget.liquidGlassStrength,
    );
    final shadows = liquidDockShadows(colorScheme);
    if (!shaderSupported) {
      return LiquidGlass(
        key: shellKey,
        style: style,
        shadows: shadows,
        child: content,
      );
    }
    return ValueListenableBuilder(
      valueListenable: _glow,
      builder: (context, glow, child) => LiquidGlass(
        key: shellKey,
        style: style,
        shadows: shadows,
        glow: glow,
        child: child,
      ),
      child: content,
    );
  }
}

/// Keeps the press light visible when the shell only paints its frosted fill.
class _FrostedDockGlow extends CustomPainter {
  _FrostedDockGlow(this.glow) : super(repaint: glow);

  final ValueListenable<LiquidGlassGlow> glow;

  @override
  void paint(Canvas canvas, Size size) {
    final current = glow.value;
    if (current.strength <= 0) return;
    final light = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: current.strength),
        Colors.transparent,
      ],
    );
    final bounds = Rect.fromCircle(
      center: current.center,
      radius: current.reach,
    );
    canvas.drawCircle(
      current.center,
      current.reach,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = light.createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_FrostedDockGlow oldDelegate) => glow != oldDelegate.glow;
}

/// Clips paint (not hit testing) to a moving lens.
class _LensClip extends CustomClipper<Path> {
  const _LensClip({required this.rect, required this.outside});

  final Rect rect;
  final bool outside;
  @override
  Path getClip(Size size) {
    final lens = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      );
    if (!outside) {
      return lens;
    }
    final full = Path()..addRect(Offset.zero & size);
    return Path.combine(ui.PathOperation.difference, full, lens);
  }

  @override
  bool shouldReclip(_LensClip oldClipper) {
    return oldClipper.rect != rect || oldClipper.outside != outside;
  }
}

/// Applies [clipper] while painting but leaves hit testing and semantics on
/// the child, so clipping the real navigation bar cannot eat taps under the
/// magnified lens.
class _PaintClipPath extends SingleChildRenderObjectWidget {
  const _PaintClipPath({required this.clipper, super.child});

  final _LensClip? clipper;

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

  final _clipLayer = LayerHandle<ClipPathLayer>();
  _LensClip? _clipper;

  set clipper(_LensClip? value) {
    final previous = _clipper;
    _clipper = value;
    if (previous == null || value == null
        ? previous != value
        : value.shouldReclip(previous)) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final clipper = _clipper;
    if (clipper == null) {
      _clipLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    _clipLayer.layer = context.pushClipPath(
      needsCompositing,
      offset,
      (Offset.zero & size).inflate(8),
      clipper.getClip(size),
      (context, offset) => super.paint(context, offset),
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
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
