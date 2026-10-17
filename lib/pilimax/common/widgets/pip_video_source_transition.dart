import 'dart:async';
import 'dart:ui' as ui;

import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:flutter/widgets.dart';

/// Keeps the last decoded PiP frame above a reused native texture while a new
/// source is becoming visible. It deliberately animates only the retained
/// frame's opacity; the player surface, geometry, and audio remain singular.
class PipVideoSourceTransition extends StatefulWidget {
  const PipVideoSourceTransition({
    super.key,
    required this.controller,
    required this.child,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.duration = const Duration(milliseconds: 180),
    this.timeout = const Duration(milliseconds: 700),
  });

  final PlPlayerController controller;
  final Widget child;
  final BoxFit fit;
  final Alignment alignment;
  final Duration duration;
  final Duration timeout;

  @override
  State<PipVideoSourceTransition> createState() =>
      _PipVideoSourceTransitionState();
}

class _PipVideoSourceTransitionState extends State<PipVideoSourceTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 0,
  )..addStatusListener(_onFadeStatus);
  late final Animation<double> _opacity =
      Tween<double>(
        begin: 1,
        end: 0,
      ).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
      );

  StreamSubscription<int>? _tokenSubscription;
  StreamSubscription<int>? _readySubscription;
  Timer? _timeoutTimer;
  ui.Image? _frame;
  int? _frameToken;
  int? _activeToken;
  PlPlayerController? _frameController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fadeController.duration =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
        ? const Duration(milliseconds: 100)
        : widget.duration;
  }

  @override
  void initState() {
    super.initState();
    _tokenSubscription = widget.controller.pipTransitionToken.listen(
      _onTokenChanged,
    );
    _readySubscription = widget.controller.pipTransitionReadyToken.listen(
      _onReadyChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onTokenChanged(widget.controller.pipTransitionToken.value);
    });
  }

  void _onTokenChanged(int token) {
    if (!mounted || token == _activeToken) {
      if (mounted) _startIfReady(token);
      return;
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _fadeController.stop();
    _releaseFrame();

    final frame = widget.controller.pipTransitionFrameForToken(token);
    final hasFrame =
        frame != null && widget.controller.hasPipTransitionFrame(token);
    setState(() {
      _activeToken = token;
      _frameToken = hasFrame ? token : null;
      _frame = hasFrame ? frame : null;
      _frameController = hasFrame ? widget.controller : null;
      _fadeController.value = 0;
    });
    if (!hasFrame) return;

    widget.controller.retainPipTransitionFrame(token);
    _timeoutTimer = Timer(widget.timeout, () => _fadeFrame(token));
    _startIfReady(token);
  }

  void _onReadyChanged(int token) => _startIfReady(token);

  void _startIfReady(int token) {
    if (!mounted ||
        token == 0 ||
        token != _frameToken ||
        widget.controller.pipTransitionReadyToken.value != token) {
      return;
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _fadeFrame(token);
  }

  void _fadeFrame(int token) {
    if (!mounted || token != _frameToken) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (!_fadeController.isAnimating && _fadeController.value == 0) {
      _fadeController.forward(from: 0);
    }
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final token = _frameToken;
      if (token != null) _releaseFrame(token);
    }
  }

  void _releaseFrame([int? token]) {
    final frameToken = token ?? _frameToken;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (frameToken != null) {
      (_frameController ?? widget.controller).releasePipTransitionFrame(
        frameToken,
      );
    }
    if (!mounted || frameToken != _frameToken) return;
    _fadeController.stop();
    setState(() {
      _frame = null;
      _frameToken = null;
      _frameController = null;
    });
  }

  @override
  void didUpdateWidget(covariant PipVideoSourceTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _fadeController.duration =
          (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
          ? const Duration(milliseconds: 100)
          : widget.duration;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      _tokenSubscription?.cancel();
      _readySubscription?.cancel();
      _releaseFrame();
      _tokenSubscription = widget.controller.pipTransitionToken.listen(
        _onTokenChanged,
      );
      _readySubscription = widget.controller.pipTransitionReadyToken.listen(
        _onReadyChanged,
      );
      _activeToken = null;
      _onTokenChanged(widget.controller.pipTransitionToken.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (frame != null)
          Positioned.fill(
            child: FadeTransition(
              opacity: _opacity,
              child: RawImage(
                image: frame,
                fit: widget.fit,
                alignment: widget.alignment,
                filterQuality: FilterQuality.low,
                isAntiAlias: false,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _tokenSubscription?.cancel();
    _readySubscription?.cancel();
    final frameController = _frameController;
    final frameToken = _frameToken;
    if (frameController != null && frameToken != null) {
      frameController.releasePipTransitionFrame(frameToken);
    }
    _fadeController
      ..removeStatusListener(_onFadeStatus)
      ..dispose();
    _frame = null;
    _frameToken = null;
    _frameController = null;
    super.dispose();
  }
}
