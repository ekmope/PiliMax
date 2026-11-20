import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:material_ui/material_ui.dart';

/// The settings pilot uses the parent value as the source of truth after a drag.
class LiquidGlassSwitch extends StatefulWidget {
  const LiquidGlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.visualScale = 1,
  }) : assert(visualScale > 0);

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  final double visualScale;

  @override
  State<LiquidGlassSwitch> createState() => _LiquidGlassSwitchState();
}

class _LiquidGlassSwitchState extends State<LiquidGlassSwitch>
    with TickerProviderStateMixin {
  // Match the Material 3 switch used by the other settings rows.
  static const _trackWidth = 52.0;
  static const _trackHeight = 32.0;
  static const _thumbTravel = _trackWidth - _trackHeight;
  static const _pressDuration = Duration(milliseconds: 140);
  static const _settleDuration = Duration(milliseconds: 180);
  static const _easeOut = Cubic(0.23, 1, 0.32, 1);

  late final _position = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
  );
  late final _lift = AnimationController(vsync: this);
  late final _motion = Listenable.merge([_position, _lift]);

  Timer? _releaseTimer;
  bool _dragging = false;
  bool _showFocus = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _releaseTimer?.cancel();
      _lift.value = 0;
      if (!_dragging) _settle();
    }
  }

  @override
  void didUpdateWidget(LiquidGlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && oldWidget.onChanged != null) {
      _dragging = false;
      _releaseTimer?.cancel();
      _lift.value = 0;
      _settle();
    } else if (widget.value != oldWidget.value && !_dragging) {
      _settle();
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _position.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _settle() {
    final target = widget.value ? 1.0 : 0.0;
    if (_reduceMotion) {
      _position.value = target;
    } else {
      _position.animateTo(target, duration: _settleDuration, curve: _easeOut);
    }
  }

  void _press() {
    _releaseTimer?.cancel();
    if (_reduceMotion || widget.onChanged == null) return;
    _lift.animateTo(1, duration: _pressDuration, curve: _easeOut);
  }

  void _release() {
    _releaseTimer?.cancel();
    if (_lift.value == 0) {
      _lift.stop();
    } else {
      _lift.animateBack(0, duration: _pressDuration, curve: _easeOut);
    }
  }

  void _toggle() => widget.onChanged?.call(!widget.value);

  void _onTap() {
    _toggle();
    if (_reduceMotion || widget.onChanged == null) return;
    _press();
    _releaseTimer = Timer(_pressDuration, _release);
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _position.stop();
    _press();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta!;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _position.value +=
        (rtl ? -delta : delta) / (_thumbTravel * widget.visualScale);
  }

  void _onDragEnd(DragEndDetails details) {
    final next = _position.value >= 0.5;
    _cancelDrag();
    if (next != widget.value) widget.onChanged?.call(next);
  }

  void _cancelDrag() {
    _dragging = false;
    _release();
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      enabled: enabled,
      onTap: enabled ? _toggle : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _toggle(),
          ),
        },
        onShowFocusHighlight: (showFocus) {
          setState(() => _showFocus = showFocus);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: enabled ? (_) => _press() : null,
          onTap: enabled ? _onTap : null,
          onTapCancel: enabled
              ? () {
                  if (!_dragging) _release();
                }
              : null,
          onHorizontalDragStart: enabled ? _onDragStart : null,
          onHorizontalDragUpdate: enabled ? _onDragUpdate : null,
          onHorizontalDragEnd: enabled ? _onDragEnd : null,
          onHorizontalDragCancel: enabled ? _cancelDrag : null,
          child: SizedBox(
            width: _trackWidth,
            height: kMinInteractiveDimension,
            child: Transform.scale(
              scale: widget.visualScale,
              alignment: Alignment.centerRight,
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => _buildVisual(context, enabled),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisual(BuildContext context, bool enabled) {
    final scheme = Theme.of(context).colorScheme;
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final position = _position.value;
    final lift = _lift.value;
    final on = widget.value;
    final focused = enabled && _showFocus;
    final trackColor = enabled
        ? Color.lerp(scheme.surfaceContainerHighest, scheme.primary, position)!
        : scheme.onSurface.withValues(alpha: 0.12);
    final thumbColor = enabled
        ? Color.lerp(scheme.outline, scheme.onPrimary, position)!
        : scheme.onSurface.withValues(alpha: 0.38);
    final thumb = DecoratedBox(
      decoration: BoxDecoration(
        color: thumbColor.withValues(alpha: thumbColor.a * (1 - 0.68 * lift)),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: on
            ? Icon(
                Icons.done,
                size: 14,
                color: enabled ? scheme.primary : scheme.surface,
              )
            : null,
      ),
    );

    // The Settings route can be opened separately from the dock's host.
    return LiquidGlassHost(
      enabled: lift > 0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: _trackWidth,
            height: _trackHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: trackColor,
                border: focused
                    ? Border.all(color: scheme.onSurface, width: 2)
                    : null,
                borderRadius: const BorderRadius.all(
                  Radius.circular(_trackHeight / 2),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(direction * (position - 0.5) * _thumbTravel, 0),
            child: Transform.scale(
              scale: lerpDouble(1, 1.4, lift)!,
              child: SizedBox.square(
                dimension: lerpDouble(16, 24, position)!,
                child: lift > 0
                    ? LiquidGlass(
                        style: LiquidGlassStyle.lens(scheme).scale(lift),
                        child: thumb,
                      )
                    : thumb,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
