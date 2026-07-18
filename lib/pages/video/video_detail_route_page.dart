import 'dart:async';

import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/pages/video/video_detail_args.dart';
import 'package:PiliMax/pages/video/video_detail_entry_overlay.dart';
import 'package:PiliMax/pages/video/video_detail_session.dart';
import 'package:PiliMax/pages/video/video_detail_transition_timing.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/pages/video/view.dart';
import 'package:PiliMax/services/live_pip_overlay_service.dart';
import 'package:PiliMax/services/pip_overlay_service.dart';
import 'package:PiliMax/services/route_restore_service.dart';
import 'package:PiliMax/services/video_transition_diagnostics.dart';
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
  static const _detailRevealDuration = videoDetailTransitionDuration;
  static const _orientationTransitionDuration = Duration(milliseconds: 180);

  late final Map<dynamic, dynamic> _arguments = VideoDetailArgs.normalize(
    Get.arguments,
  );
  late final AnimationController _detailRevealController;
  late VideoDetailSkeletonVariant _entryVariant;
  bool? _entryIsVertical;
  late VideoDetailSkeletonProfile _entryContentProfile;
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
  bool _showStaticEntryCover = false;
  bool _pendingPresentationReady = false;
  bool _isResolving = false;
  Object? _error;
  Object? _pendingResolutionError;
  int? _detailRevealDiagnosticId;
  VideoDetailExitMode? _preparedExitMode;

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

  bool get _entryExitInProgress =>
      _preparedExitMode == VideoDetailExitMode.entryReverse ||
      _preparedExitMode == VideoDetailExitMode.routeComposite;

  bool get _entryReverseInProgress =>
      _preparedExitMode == VideoDetailExitMode.entryReverse;

  bool get _externalEntryOwnsPresentation =>
      _usesExternalEntryOverlay ||
      (_showEntryLayer &&
          _entryOverlay != null &&
          (_entryReverseInProgress ||
              (_preparedExitMode == null &&
                  (_routeAnimation?.status == AnimationStatus.reverse ||
                      _routeAnimation?.status == AnimationStatus.dismissed))));

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
    if (status == AnimationStatus.completed) {
      _finishDetailRevealDiagnostic('completed');
      if (mounted && _showEntryLayer) {
        setState(() => _showEntryLayer = false);
      }
    }
  }

  VideoDetailExitMode _prepareForExit() {
    if (!mounted) {
      return VideoDetailExitMode.detail;
    }
    final preparedExitMode = _preparedExitMode;
    if (preparedExitMode != null) {
      return preparedExitMode;
    }
    _finishDetailRevealDiagnostic('interrupted');

    // While the entry presentation is still authoritative, let the route,
    // Hero, and external overlay reverse along their original animation.
    if (_showEntryLayer && !_revealingDetail && _usesExternalEntryOverlay) {
      setState(() {
        _preparedExitMode = VideoDetailExitMode.entryReverse;
      });
      _entryOverlay?.beginReversibleExit();
      return VideoDetailExitMode.entryReverse;
    }

    // A route without an external overlay still owns a complete skeleton and
    // cover. Keep that composite intact instead of replacing it with a solid
    // surface while the shared geometry returns to the source card.
    if (_showEntryLayer && !_revealingDetail) {
      _preparedExitMode = VideoDetailExitMode.routeComposite;
      setState(() {
        _showStaticEntryCover = _hasVideoTransition;
        _useHeroTarget = false;
      });
      return VideoDetailExitMode.routeComposite;
    }

    _entryOverlay?.abort();
    if (!_showEntryLayer) {
      return _preparedExitMode = VideoDetailExitMode.detail;
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
    return _preparedExitMode = VideoDetailExitMode.detail;
  }

  void _cancelPreparedExit() {
    final preparedExitMode = _preparedExitMode;
    _preparedExitMode = null;
    if (!mounted || preparedExitMode == null) {
      return;
    }
    switch (preparedExitMode) {
      case VideoDetailExitMode.entryReverse:
        setState(() {});
        _entryOverlay?.cancelReversibleExit();
        _resumeDeferredEntryHandoff();
        break;
      case VideoDetailExitMode.routeComposite:
        setState(() {
          _showStaticEntryCover = false;
          _useHeroTarget = true;
        });
        _resumeDeferredEntryHandoff();
        break;
      case VideoDetailExitMode.detail:
        break;
    }
  }

  void _resumeDeferredEntryHandoff() {
    if (!mounted || _entryExitInProgress) {
      return;
    }
    final pendingResolutionError = _pendingResolutionError;
    if (pendingResolutionError != null) {
      _pendingResolutionError = null;
      _showResolutionError(pendingResolutionError);
      return;
    }
    if (_pendingPresentationReady) {
      _pendingPresentationReady = false;
      _presentationReady = true;
    }
    if (_pendingEntryOrientation != null ||
        _pendingEntryVariant != null ||
        _pendingContentProfile != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyPendingEntryProfile(),
      );
      return;
    }
    if (_showDetail && _showEntryLayer && !_usesExternalEntryOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _beginDetailReveal());
    } else {
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
    _entryContentProfile = VideoDetailSession.skeletonProfileFor(_arguments);
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
        if (_entryExitInProgress) {
          _pendingResolutionError = error;
        } else {
          _showResolutionError(error);
        }
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
    if (_entryExitInProgress) {
      _pendingEntryOrientation = orientation;
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
    if (_entryExitInProgress) {
      _pendingContentProfile = profile;
      return;
    }
    _stageContentProfile(profile);
  }

  static bool _sameContentProfile(
    VideoDetailSkeletonProfile first,
    VideoDetailSkeletonProfile second,
  ) =>
      first.hasSeasonPanel == second.hasSeasonPanel &&
      first.hasPagesPanel == second.hasPagesPanel &&
      first.tabCount == second.tabCount &&
      first.actionCount == second.actionCount &&
      first.hasEpisodePanel == second.hasEpisodePanel;

  void _stageEntryOrientation(bool? orientation) {
    if (orientation == null || orientation == _entryIsVertical) {
      return;
    }
    if (_entryExitInProgress || !_routeAnimationCompleted) {
      _pendingEntryOrientation = orientation;
      return;
    }
    _applyEntryOrientation(orientation);
  }

  void _stageEntryVariant(VideoDetailSkeletonVariant variant) {
    if (variant == _entryVariant) {
      return;
    }
    if (_entryExitInProgress || !_routeAnimationCompleted) {
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
    if (_entryExitInProgress || !_routeAnimationCompleted) {
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
    if (!mounted || _entryExitInProgress) {
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
    if (_entryExitInProgress) {
      _pendingEntryOrientation = orientation;
      _pendingEntryVariant = variant;
      _pendingContentProfile = contentProfile;
      return;
    }
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
      tabCount: contentProfile.tabCount,
      actionCount: contentProfile.actionCount,
      hasEpisodePanel: contentProfile.hasEpisodePanel,
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
    if (_entryExitInProgress) {
      _pendingPresentationReady = true;
      return;
    }
    _presentationReady = true;
    _tryMountDetail();
  }

  void _tryMountDetail() {
    if (_entryExitInProgress) {
      return;
    }
    if (_usesExternalEntryOverlay) {
      if (!mounted ||
          !_argumentsResolved ||
          _session == null ||
          !_routeAnimationCompleted ||
          _pendingEntryOrientation != null ||
          _pendingEntryVariant != null ||
          _pendingContentProfile != null ||
          _orientationSettling) {
        return;
      }
      if (!_showDetail) {
        setState(() => _showDetail = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryMountDetail());
        return;
      }
      if (!_presentationReady && !_fallbackElapsed) {
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
        _entryExitInProgress ||
        !_showDetail ||
        !_showEntryLayer ||
        _pendingEntryOrientation != null ||
        _pendingEntryVariant != null ||
        _pendingContentProfile != null ||
        _orientationSettling ||
        _revealingDetail) {
      return;
    }
    _finishDetailRevealDiagnostic('superseded');
    _detailRevealDiagnosticId = VideoTransitionDiagnostics.begin(
      VideoTransitionDiagnosticKind.detailReveal,
      expectedDuration: _entryOverlay?.revealDuration ?? _detailRevealDuration,
    );
    setState(() {
      // Removing the Hero target here prevents any reverse skeleton flight.
      _useHeroTarget = false;
      _revealingDetail = true;
    });
    final entryOverlay = _entryOverlay;
    if (entryOverlay != null) {
      unawaited(
        entryOverlay.beginReveal().whenComplete(() {
          _finishDetailRevealDiagnostic(
            entryOverlay.didCompleteReveal ? 'completed' : 'aborted',
          );
          if (mounted && _showEntryLayer) {
            setState(() => _showEntryLayer = false);
          }
        }),
      );
      return;
    }
    _detailRevealController.forward(from: 0);
  }

  void _finishDetailRevealDiagnostic(String outcome) {
    final captureId = _detailRevealDiagnosticId;
    _detailRevealDiagnosticId = null;
    VideoTransitionDiagnostics.finish(captureId, outcome: outcome);
  }

  void _retry() {
    setState(() => _error = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveArguments());
  }

  void _showResolutionError(Object error) {
    _entryOverlay?.abort();
    setState(() {
      _error = error;
      _showEntryLayer = false;
      _useHeroTarget = false;
    });
  }

  Widget _entryCoverLayer(
    BuildContext context, {
    required bool enableHero,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    final topInset = Pref.removeSafeArea
        ? 0.0
        : MediaQuery.viewPaddingOf(context).top;
    final playerRect = VideoDetailLayoutMetrics.entryPlayerRect(
      viewport,
      isVertical: _entryIsVertical,
      topInset: topInset,
    );
    final cover = _entryCover;
    final coverLayer = cover == null
        ? const ColoredBox(color: Colors.black)
        : NetworkImgLayer(
            src: cover,
            width: playerRect.width,
            height: playerRect.height,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            borderRadius: BorderRadius.zero,
            clip: false,
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedPositioned(
          duration: _orientationTransitionDuration,
          curve: Curves.easeInOutCubic,
          left: playerRect.left,
          top: playerRect.top,
          width: playerRect.width,
          height: playerRect.height,
          child: HeroMode(
            enabled: enableHero,
            child: VideoDetailHero.target(tag: _heroTag, child: coverLayer),
          ),
        ),
      ],
    );
  }

  Widget _entryShell() => VideoDetailHeroShell.revealing(
    key: ValueKey((
      _entryIsVertical,
      _skeletonVariant,
      !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasSeasonPanel,
      !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasPagesPanel,
      _entryContentProfile.tabCount,
      _entryContentProfile.actionCount,
      _entryContentProfile.hasEpisodePanel,
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
    tabCount: _entryContentProfile.tabCount,
    actionCount: _entryContentProfile.actionCount,
    hasEpisodePanel: _entryContentProfile.hasEpisodePanel,
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
    _finishDetailRevealDiagnostic('disposed');
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
    final showHeroTarget = _useHeroTarget && _hasVideoTransition;
    final showStaticEntryCover =
        _showStaticEntryCover && _showEntryLayer && !showHeroTarget;
    final hideDetail = _hideDetailDuringHeroFlight || _entryReverseInProgress;
    if (!_showDetail) {
      return Scaffold(
        backgroundColor: showHeroTarget || _externalEntryOwnsPresentation
            ? Colors.transparent
            : colorScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!_externalEntryOwnsPresentation)
              IgnorePointer(child: _animatedEntryShell()),
            if (showHeroTarget || showStaticEntryCover)
              IgnorePointer(
                child: _entryCoverLayer(context, enableHero: showHeroTarget),
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
          ignoring: hideDetail,
          child: Opacity(
            opacity: hideDetail ? 0 : 1,
            child: VideoDetailPageV(session: _session),
          ),
        ),
        if (_showEntryLayer && !_externalEntryOwnsPresentation)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _detailRevealController,
                builder: (context, _) => _animatedEntryShell(),
              ),
            ),
          ),
        if (showHeroTarget || showStaticEntryCover)
          Positioned.fill(
            child: IgnorePointer(
              child: _entryCoverLayer(context, enableHero: showHeroTarget),
            ),
          ),
      ],
    );
  }
}
