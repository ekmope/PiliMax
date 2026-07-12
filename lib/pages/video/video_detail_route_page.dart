import 'dart:async';

import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_detail_args.dart';
import 'package:PiliMax/pages/video/video_detail_session.dart';
import 'package:PiliMax/pages/video/view.dart';
import 'package:PiliMax/services/live_pip_overlay_service.dart';
import 'package:PiliMax/services/pip_overlay_service.dart';
import 'package:PiliMax/utils/page_utils.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Resolves and preloads video data while the source card expands.
class VideoDetailRoutePage extends StatefulWidget {
  const VideoDetailRoutePage({super.key});

  @override
  State<VideoDetailRoutePage> createState() => _VideoDetailRoutePageState();
}

class _VideoDetailRoutePageState extends State<VideoDetailRoutePage> {
  static const _maximumPostTransitionHold = Duration(milliseconds: 1200);
  static const _detailRevealDuration = Duration(milliseconds: 180);

  late final Map<dynamic, dynamic> _arguments = VideoDetailArgs.normalize(
    Get.arguments,
  );
  late final bool? _entryIsVertical;
  Animation<double>? _routeAnimation;
  VideoDetailSession? _session;
  Timer? _fallbackTimer;
  Timer? _removeEntryTimer;
  bool _routeAnimationCompleted = false;
  bool _argumentsResolved = false;
  bool _presentationReady = false;
  bool _fallbackElapsed = false;
  bool _showDetail = false;
  bool _showEntryLayer = true;
  bool _useHeroTarget = true;
  bool _entryVisible = true;
  bool _revealingDetail = false;
  bool _isResolving = false;
  Object? _error;

  bool get _hasPendingLaunch =>
      _arguments[PageUtils.videoPendingLaunchKey] is VideoPendingLaunchType;

  String get _heroTag => _arguments['heroTag'] as String;

  bool get _fromPip => _arguments['fromPip'] == true;

  bool get _needsImmediatePipTakeover =>
      _fromPip ||
      PipOverlayService.isInPipMode ||
      LivePipOverlayService.isInPipMode;

  bool get _hasVideoTransition =>
      _arguments[videoTransitionTokenKey] is VideoTransitionToken;

  bool get _hideDetailDuringHeroFlight =>
      _showDetail &&
      _useHeroTarget &&
      _hasVideoTransition &&
      !_routeAnimationCompleted;

  @override
  void initState() {
    super.initState();
    _entryIsVertical = _arguments['videoOrientationKnown'] == true
        ? _arguments['isVertical'] as bool?
        : null;
    if (_hasPendingLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveArguments());
    } else {
      _argumentsResolved = true;
      _startSession();
      if (_needsImmediatePipTakeover) {
        _showDetail = true;
        if (_fromPip) {
          _showEntryLayer = false;
          _useHeroTarget = false;
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _routeAnimation = animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _markRouteAnimationCompleted();
    } else {
      animation.addStatusListener(_onRouteAnimationStatus);
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _markRouteAnimationCompleted();
    }
  }

  void _markRouteAnimationCompleted() {
    if (_routeAnimationCompleted) {
      return;
    }
    _routeAnimationCompleted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _useHeroTarget) {
        setState(() => _useHeroTarget = false);
      }
      if (mounted && _showDetail && _showEntryLayer) {
        _beginDetailReveal();
      }
    });
    _fallbackTimer ??= Timer(_maximumPostTransitionHold, () {
      if (!mounted) {
        return;
      }
      _fallbackElapsed = true;
      _tryMountDetail();
    });
    _tryMountDetail();
  }

  Future<void> _resolveArguments() async {
    if (_isResolving) {
      return;
    }
    _isResolving = true;
    try {
      await PageUtils.resolvePendingVideoLaunch(_arguments);
      if (!mounted) {
        return;
      }
      setState(() {
        _argumentsResolved = true;
        _error = null;
      });
      _startSession();
      if (_needsImmediatePipTakeover) {
        setState(() {
          _showDetail = true;
          if (_fromPip) {
            _showEntryLayer = false;
            _useHeroTarget = false;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      _isResolving = false;
    }
  }

  void _startSession() {
    final session = VideoDetailSession.start(_arguments);
    _session = session;
    _arguments[videoDetailSessionKey] = session;
    (_arguments[videoTransitionTokenKey] as VideoTransitionToken?)
        ?.bindLaunchContentKey(session.launchContentKey);
    session.presentationReady.then(
      (_) => _markPresentationReady(session),
      onError: (_, _) => _markPresentationReady(session),
    );
    _tryMountDetail();
  }

  void _markPresentationReady(VideoDetailSession session) {
    if (!mounted || !identical(session, _session)) {
      return;
    }
    _presentationReady = true;
    _tryMountDetail();
  }

  void _tryMountDetail() {
    if (!mounted ||
        _showDetail ||
        !_argumentsResolved ||
        !_routeAnimationCompleted ||
        (!_presentationReady && !_fallbackElapsed)) {
      return;
    }
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    setState(() => _showDetail = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginDetailReveal());
  }

  void _beginDetailReveal() {
    if (!mounted || !_showDetail || !_showEntryLayer || !_entryVisible) {
      return;
    }
    setState(() {
      // Removing the Hero target here prevents any reverse skeleton flight.
      _useHeroTarget = false;
      _revealingDetail = true;
      _entryVisible = false;
    });
    _removeEntryTimer = Timer(_detailRevealDuration, () {
      if (mounted) {
        setState(() => _showEntryLayer = false);
      }
    });
  }

  void _retry() {
    setState(() => _error = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveArguments());
  }

  Widget _heroTarget() => VideoDetailHero.target(
    tag: _heroTag,
    child: VideoDetailHeroShell(isVertical: _entryIsVertical),
  );

  Widget _entryShell() => _revealingDetail && _entryIsVertical == null
      ? ColoredBox(color: Theme.of(context).colorScheme.surface)
      : VideoDetailHeroShell(isVertical: _entryIsVertical);

  Widget _errorOverlay(BuildContext context, Object error) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: Get.back,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 36,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _removeEntryTimer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _session?.dispose();
    (_arguments[videoTransitionTokenKey] as VideoTransitionToken?)?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!_showDetail) {
      return Scaffold(
        backgroundColor: _useHeroTarget && _hasVideoTransition
            ? Colors.transparent
            : colorScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: _useHeroTarget ? _heroTarget() : _entryShell(),
            ),
            if (_error case final error?) _errorOverlay(context, error),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: _hideDetailDuringHeroFlight,
          child: Opacity(
            opacity: _hideDetailDuringHeroFlight ? 0 : 1,
            child: VideoDetailPageV(session: _session),
          ),
        ),
        if (_showEntryLayer)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _entryVisible ? 1 : 0,
                duration: _detailRevealDuration,
                curve: Curves.easeOutCubic,
                child: _useHeroTarget ? _heroTarget() : _entryShell(),
              ),
            ),
          ),
      ],
    );
  }
}
