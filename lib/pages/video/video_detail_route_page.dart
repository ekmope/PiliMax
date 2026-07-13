import 'dart:async';

import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/pages/video/video_detail_args.dart';
import 'package:PiliMax/pages/video/video_detail_entry_overlay.dart';
import 'package:PiliMax/pages/video/video_detail_session.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/pages/video/view.dart';
import 'package:PiliMax/services/live_pip_overlay_service.dart';
import 'package:PiliMax/services/pip_overlay_service.dart';
import 'package:PiliMax/services/route_restore_service.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Resolves and preloads video data while the source card expands.
class VideoDetailRoutePage extends StatefulWidget {
  const VideoDetailRoutePage({super.key});

  @override
  State<VideoDetailRoutePage> createState() => _VideoDetailRoutePageState();
}

class _VideoDetailRoutePageState extends State<VideoDetailRoutePage>
    with SingleTickerProviderStateMixin {
  static const _maximumPostTransitionHold = Duration(milliseconds: 1200);
  static const _detailRevealDuration = Duration(milliseconds: 320);
  static const _orientationTransitionDuration = Duration(milliseconds: 180);

  late final Map<dynamic, dynamic> _arguments = VideoDetailArgs.normalize(
    Get.arguments,
  );
  late final AnimationController _detailRevealController;
  late VideoDetailSkeletonVariant _entryVariant;
  bool? _entryIsVertical;
  VideoDetailSkeletonProfile _entryContentProfile =
      const VideoDetailSkeletonProfile();
  Animation<double>? _routeAnimation;
  bool _routeAnimationAttachScheduled = false;
  VideoDetailSession? _session;
  Timer? _fallbackTimer;
  Timer? _orientationSettleTimer;
  late final VideoDetailPrepareForExit _prepareForExitCallback;
  late final VoidCallback _cancelPreparedExitCallback;
  bool? _pendingEntryOrientation;
  VideoDetailSkeletonVariant? _pendingEntryVariant;
  VideoDetailSkeletonProfile? _pendingContentProfile;
  bool _routeAnimationCompleted = false;
  bool _argumentsResolved = false;
  bool _presentationReady = false;
  bool _fallbackElapsed = false;
  bool _showDetail = false;
  bool _showEntryLayer = true;
  bool _useHeroTarget = true;
  bool _revealingDetail = false;
  bool _orientationSettling = false;
  bool _showEarlyExitSurface = false;
  bool _isResolving = false;
  Object? _error;

  bool get _hasPendingLaunch =>
      _arguments[PageUtils.videoPendingLaunchKey] is VideoPendingLaunchType;

  String get _heroTag => _arguments['heroTag'] as String;

  String? get _entryTitle {
    final title = _arguments['title'];
    return title is String ? title : null;
  }

  String? get _entryCover {
    final cover = _arguments['cover'];
    return cover is String && cover.isNotEmpty ? cover : null;
  }

  bool get _fromPip => _arguments['fromPip'] == true;

  bool get _needsImmediatePipTakeover =>
      _fromPip ||
      PipOverlayService.isInPipMode ||
      LivePipOverlayService.isInPipMode;

  bool get _hasVideoTransition =>
      _arguments[videoTransitionTokenKey] is VideoTransitionToken;

  VideoDetailEntryOverlayController? get _entryOverlay =>
      _arguments[videoDetailEntryOverlayKey]
          as VideoDetailEntryOverlayController?;

  bool get _usesExternalEntryOverlay => _entryOverlay?.isActive == true;

  VideoDetailSkeletonVariant get _skeletonVariant => _entryVariant;

  VideoDetailSkeletonVariant _resolvedSkeletonVariant() {
    if (_arguments['sourceType'] == SourceType.file) {
      return VideoDetailSkeletonVariant.local;
    }
    final videoType = _arguments['videoType'];
    if (videoType == VideoType.pgc) {
      return VideoDetailSkeletonVariant.pgc;
    }
    if (videoType == VideoType.pugv) {
      return VideoDetailSkeletonVariant.pugv;
    }
    return VideoDetailSkeletonVariant.ugc;
  }

  bool get _hideDetailDuringHeroFlight =>
      _showDetail &&
      _useHeroTarget &&
      _hasVideoTransition &&
      !_routeAnimationCompleted;

  bool? _resolvedEntryOrientation() =>
      _arguments['videoOrientationKnown'] == true
      ? _arguments['isVertical'] as bool?
      : null;

  void _onDetailRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _showEntryLayer) {
      setState(() => _showEntryLayer = false);
    }
  }

  bool _prepareForExit() {
    if (!mounted) {
      return false;
    }
    _entryOverlay?.abort();
    if (!_showEntryLayer) {
      return true;
    }
    if (!_showDetail && (!_argumentsResolved || _session == null)) {
      setState(() {
        _showEarlyExitSurface = true;
        _useHeroTarget = false;
      });
      return false;
    }
    _detailRevealController.stop();
    _orientationSettleTimer?.cancel();
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    setState(() {
      _showDetail = true;
      _showEntryLayer = false;
      _useHeroTarget = false;
      _revealingDetail = true;
      _orientationSettling = false;
      _pendingEntryOrientation = null;
      _pendingEntryVariant = null;
      _pendingContentProfile = null;
    });
    return true;
  }

  void _cancelPreparedExit() {
    if (mounted && _showEarlyExitSurface) {
      setState(() => _showEarlyExitSurface = false);
      _tryMountDetail();
    }
  }

  @override
  void initState() {
    super.initState();
    _detailRevealController = AnimationController(
      vsync: this,
      duration: _detailRevealDuration,
    )..addStatusListener(_onDetailRevealStatus);
    _prepareForExitCallback = _prepareForExit;
    _cancelPreparedExitCallback = _cancelPreparedExit;
    _arguments[videoDetailPrepareForExitKey] = _prepareForExitCallback;
    _arguments[videoDetailCancelPreparedExitKey] = _cancelPreparedExitCallback;
    _entryVariant = _resolvedSkeletonVariant();
    _entryIsVertical = _resolvedEntryOrientation();
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
    _attachRouteAnimation();
  }

  void _attachRouteAnimation() {
    final route = ModalRoute.of(context);
    if (route?.offstage == true) {
      _entryOverlay?.bindRouteAnimation(null);
      if (!_routeAnimationAttachScheduled) {
        _routeAnimationAttachScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _routeAnimationAttachScheduled = false;
          if (mounted) {
            _attachRouteAnimation();
          }
        });
      }
      return;
    }
    final animation = route?.animation;
    if (identical(animation, _routeAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _routeAnimation = animation;
    _entryOverlay?.bindRouteAnimation(animation);
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
      if (!mounted) {
        return;
      }
      final settleOrientationBeforeHandoff =
          _pendingEntryOrientation != null &&
          _pendingEntryOrientation != _entryIsVertical;
      if (_useHeroTarget && !settleOrientationBeforeHandoff) {
        setState(() => _useHeroTarget = false);
      }
      if (_pendingEntryOrientation != null ||
          _pendingEntryVariant != null ||
          _pendingContentProfile != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _applyPendingEntryProfile(),
        );
      } else if (_showDetail && _showEntryLayer) {
        if (_usesExternalEntryOverlay) {
          _tryMountDetail();
        } else {
          _beginDetailReveal();
        }
      }
    });
    if (!_usesExternalEntryOverlay) {
      _fallbackTimer ??= Timer(_maximumPostTransitionHold, () {
        if (!mounted) {
          return;
        }
        _fallbackElapsed = true;
        _tryMountDetail();
      });
    }
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
      final resolvedOrientation = _resolvedEntryOrientation();
      final resolvedVariant = _resolvedSkeletonVariant();
      setState(() {
        _argumentsResolved = true;
        _error = null;
      });
      _stageEntryOrientation(resolvedOrientation);
      _stageEntryVariant(resolvedVariant);
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
        _entryOverlay?.abort();
        setState(() {
          _error = error;
          _showEntryLayer = false;
          _useHeroTarget = false;
        });
      }
    } finally {
      _isResolving = false;
    }
  }

  void _startSession() {
    final session = VideoDetailSession.start(_arguments);
    _session = session;
    unawaited(RouteRestoreService.saveVideoRoute(_arguments));
    _arguments[videoDetailSessionKey] = session;
    (_arguments[videoTransitionTokenKey] as VideoTransitionToken?)
        ?.bindLaunchContentKey(session.launchContentKey);
    session.launchOrientationReady.then(
      (orientation) => _markEntryOrientation(session, orientation),
    );
    session.skeletonProfileReady.then(
      (profile) => _markContentProfile(session, profile),
    );
    session.presentationReady.then(
      (_) => _markPresentationReady(session),
      onError: (_, _) => _markPresentationReady(session),
    );
    if (_usesExternalEntryOverlay && !_showDetail) {
      setState(() => _showDetail = true);
    }
    _tryMountDetail();
  }

  void _markEntryOrientation(
    VideoDetailSession session,
    bool? orientation,
  ) {
    if (!mounted ||
        !identical(session, _session) ||
        orientation == null ||
        orientation == _entryIsVertical ||
        _revealingDetail) {
      return;
    }
    _stageEntryOrientation(orientation);
  }

  void _markContentProfile(
    VideoDetailSession session,
    VideoDetailSkeletonProfile profile,
  ) {
    if (Pref.alwaysExpandIntroPanel ||
        !mounted ||
        !identical(session, _session) ||
        _sameContentProfile(profile, _entryContentProfile) ||
        _revealingDetail) {
      return;
    }
    _stageContentProfile(profile);
  }

  static bool _sameContentProfile(
    VideoDetailSkeletonProfile first,
    VideoDetailSkeletonProfile second,
  ) =>
      first.hasSeasonPanel == second.hasSeasonPanel &&
      first.hasPagesPanel == second.hasPagesPanel;

  void _stageEntryOrientation(bool? orientation) {
    if (orientation == null || orientation == _entryIsVertical) {
      return;
    }
    if (!_routeAnimationCompleted || _useHeroTarget) {
      _pendingEntryOrientation = orientation;
      return;
    }
    _applyEntryOrientation(orientation);
  }

  void _stageEntryVariant(VideoDetailSkeletonVariant variant) {
    if (variant == _entryVariant) {
      return;
    }
    if (!_routeAnimationCompleted || _useHeroTarget) {
      _pendingEntryVariant = variant;
      return;
    }
    _applyEntryProfile(
      orientation: _entryIsVertical,
      variant: variant,
      contentProfile: _entryContentProfile,
    );
  }

  void _stageContentProfile(VideoDetailSkeletonProfile profile) {
    if (_sameContentProfile(profile, _entryContentProfile)) {
      return;
    }
    if (!_routeAnimationCompleted || _useHeroTarget) {
      _pendingContentProfile = profile;
      return;
    }
    _applyEntryProfile(
      orientation: _entryIsVertical,
      variant: _entryVariant,
      contentProfile: profile,
    );
  }

  void _applyPendingEntryProfile() {
    if (!mounted) {
      return;
    }
    final orientation = _pendingEntryOrientation ?? _entryIsVertical;
    final variant = _pendingEntryVariant ?? _entryVariant;
    final contentProfile = _pendingContentProfile ?? _entryContentProfile;
    _pendingEntryOrientation = null;
    _pendingEntryVariant = null;
    _pendingContentProfile = null;
    if (orientation == _entryIsVertical &&
        variant == _entryVariant &&
        _sameContentProfile(contentProfile, _entryContentProfile)) {
      if (_showDetail && !_usesExternalEntryOverlay) {
        _beginDetailReveal();
      } else {
        _tryMountDetail();
      }
      return;
    }
    _applyEntryProfile(
      orientation: orientation,
      variant: variant,
      contentProfile: contentProfile,
    );
  }

  void _applyEntryOrientation(bool orientation) => _applyEntryProfile(
    orientation: orientation,
    variant: _entryVariant,
    contentProfile: _entryContentProfile,
  );

  void _applyEntryProfile({
    required bool? orientation,
    required VideoDetailSkeletonVariant variant,
    required VideoDetailSkeletonProfile contentProfile,
  }) {
    _orientationSettleTimer?.cancel();
    _orientationSettleTimer = null;
    setState(() {
      _entryIsVertical = orientation;
      _entryVariant = variant;
      _entryContentProfile = contentProfile;
      _orientationSettling = true;
    });
    _entryOverlay?.updateProfile(
      isVertical: orientation,
      variant: variant,
      title: _entryTitle,
      hasSeasonPanel:
          !Pref.alwaysExpandIntroPanel && contentProfile.hasSeasonPanel,
      hasPagesPanel:
          !Pref.alwaysExpandIntroPanel && contentProfile.hasPagesPanel,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_orientationSettling ||
          orientation != _entryIsVertical ||
          variant != _entryVariant ||
          !_sameContentProfile(contentProfile, _entryContentProfile)) {
        return;
      }
      _orientationSettleTimer = Timer(_orientationTransitionDuration, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _orientationSettleTimer = null;
          _orientationSettling = false;
          if (_usesExternalEntryOverlay) {
            _useHeroTarget = false;
          }
        });
        if (_showDetail && !_usesExternalEntryOverlay) {
          _beginDetailReveal();
        } else {
          _tryMountDetail();
        }
      });
    });
  }

  Future<void> _markPresentationReady(VideoDetailSession session) async {
    final profile = await session.skeletonProfileReady;
    if (!mounted || !identical(session, _session)) {
      return;
    }
    _markContentProfile(session, profile);
    _presentationReady = true;
    _tryMountDetail();
  }

  void _tryMountDetail() {
    if (_usesExternalEntryOverlay) {
      if (!mounted || !_argumentsResolved || _session == null) {
        return;
      }
      if (!_showDetail) {
        setState(() => _showDetail = true);
      }
      if (!_routeAnimationCompleted ||
          _pendingEntryOrientation != null ||
          _pendingEntryVariant != null ||
          _pendingContentProfile != null ||
          _orientationSettling ||
          !_presentationReady) {
        return;
      }
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _beginDetailReveal());
      return;
    }
    if (!mounted ||
        _showDetail ||
        !_argumentsResolved ||
        !_routeAnimationCompleted ||
        _pendingEntryOrientation != null ||
        _pendingEntryVariant != null ||
        _pendingContentProfile != null ||
        _orientationSettling ||
        (!_presentationReady && !_fallbackElapsed)) {
      return;
    }
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    setState(() => _showDetail = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginDetailReveal());
  }

  void _beginDetailReveal() {
    if (!mounted ||
        !_showDetail ||
        !_showEntryLayer ||
        _pendingEntryOrientation != null ||
        _pendingEntryVariant != null ||
        _pendingContentProfile != null ||
        _orientationSettling ||
        _revealingDetail) {
      return;
    }
    setState(() {
      // Removing the Hero target here prevents any reverse skeleton flight.
      _useHeroTarget = false;
      _revealingDetail = true;
    });
    final entryOverlay = _entryOverlay;
    if (entryOverlay != null) {
      unawaited(
        entryOverlay.beginReveal().whenComplete(() {
          if (mounted && _showEntryLayer) {
            setState(() => _showEntryLayer = false);
          }
        }),
      );
      return;
    }
    _detailRevealController.forward(from: 0);
  }

  void _retry() {
    setState(() => _error = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveArguments());
  }

  Widget _heroTarget(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final topInset = Pref.removeSafeArea
        ? 0.0
        : MediaQuery.viewPaddingOf(context).top;
    final playerBottom = VideoDetailLayoutMetrics.entryPlayerBottom(
      viewport,
      isVertical: _entryIsVertical,
      topInset: topInset,
    );
    final cover = _entryCover;
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: _orientationTransitionDuration,
        curve: Curves.easeInOutCubic,
        width: viewport.width,
        height: playerBottom,
        child: VideoDetailHero.target(
          tag: _heroTag,
          child: cover == null
              ? const ColoredBox(color: Colors.black)
              : NetworkImgLayer(
                  src: cover,
                  width: viewport.width,
                  height: playerBottom,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  borderRadius: BorderRadius.zero,
                  clip: false,
                ),
        ),
      ),
    );
  }

  Widget _entryShell() => VideoDetailHeroShell.revealing(
    key: ValueKey((
      _entryIsVertical,
      _skeletonVariant,
      !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasSeasonPanel,
      !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasPagesPanel,
    )),
    progress: _revealingDetail ? _detailRevealController.value : 0,
    isVertical: _entryIsVertical,
    variant: _skeletonVariant,
    title: _entryTitle,
    expandedIntro: Pref.alwaysExpandIntroPanel,
    showRecommendations: Pref.showRelatedVideo && !Pref.alwaysExpandIntroPanel,
    hasSeasonPanel:
        !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasSeasonPanel,
    hasPagesPanel:
        !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasPagesPanel,
  );

  Widget _animatedEntryShell() => AnimatedSwitcher(
    duration: _orientationTransitionDuration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    child: _entryShell(),
  );

  Widget _errorOverlay(BuildContext context, Object error) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: SafeArea(
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
      ),
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _orientationSettleTimer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _detailRevealController
      ..removeStatusListener(_onDetailRevealStatus)
      ..dispose();
    if (identical(
      _arguments[videoDetailPrepareForExitKey],
      _prepareForExitCallback,
    )) {
      _arguments.remove(videoDetailPrepareForExitKey);
    }
    if (identical(
      _arguments[videoDetailCancelPreparedExitKey],
      _cancelPreparedExitCallback,
    )) {
      _arguments.remove(videoDetailCancelPreparedExitKey);
    }
    _session?.dispose();
    _entryOverlay?.dispose();
    (_arguments[videoTransitionTokenKey] as VideoTransitionToken?)?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_showEarlyExitSurface) {
      return ColoredBox(color: colorScheme.surface);
    }
    final showHeroTarget = _useHeroTarget && _hasVideoTransition;
    if (!_showDetail) {
      return Scaffold(
        backgroundColor: showHeroTarget || _usesExternalEntryOverlay
            ? Colors.transparent
            : colorScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!_usesExternalEntryOverlay)
              IgnorePointer(child: _animatedEntryShell()),
            if (showHeroTarget) IgnorePointer(child: _heroTarget(context)),
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
        if (_showEntryLayer && !_usesExternalEntryOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _detailRevealController,
                builder: (context, _) => _animatedEntryShell(),
              ),
            ),
          ),
        if (showHeroTarget)
          Positioned.fill(
            child: IgnorePointer(child: _heroTarget(context)),
          ),
      ],
    );
  }
}
