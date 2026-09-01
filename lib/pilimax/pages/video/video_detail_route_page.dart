import 'dart:async';

import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_back_progress.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_args.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_entry_overlay.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_session.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_transition_timing.dart';
import 'package:PiliMax/pilimax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/pages/video/view.dart';
import 'package:PiliMax/pilimax/services/live_pip_overlay_service.dart';
import 'package:PiliMax/pilimax/services/pip_overlay_service.dart';
import 'package:PiliMax/pilimax/services/route_restore_service.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';

import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

/// Resolves and preloads video data while the source card expands.
class VideoDetailRoutePage extends StatefulWidget {
  const VideoDetailRoutePage({super.key});

  @override
  State<VideoDetailRoutePage> createState() => _VideoDetailRoutePageState();
}

class _VideoDetailRoutePageState extends State<VideoDetailRoutePage>
    with SingleTickerProviderStateMixin {
  static const _maximumPostTransitionHold =
      videoDetailMaximumPostTransitionHold;
  static const _detailRevealDuration = videoDetailRevealDuration;
  static const _orientationTransitionDuration =
      videoDetailProfileTransitionDuration;
  static const _playerHandoffFadeDuration = Duration(milliseconds: 100);
  // The detail page reveals independently. This timeout only prevents a
  // missing platform frame signal from leaving the media cover permanently.
  static const _playerHandoffForceReleaseTimeout = Duration(seconds: 6);

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
  Timer? _playerHandoffForceReleaseTimer;
  final GlobalKey _entryMediaLayerKey = GlobalKey();
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
  bool _showPlayerHandoffCover = false;
  bool _playerHandoffCoverOpaque = true;
  bool _initialDetailLayoutReady = false;
  bool _initialPlayerVisualReady = false;
  bool _playerHandoffForceRelease = false;
  bool _preparedExitUsesPlayerHandoff = false;
  bool _pendingPresentationReady = false;
  bool _isResolving = false;
  int _playerHandoffGeneration = 0;
  int _entryRevealGeneration = 0;
  Object? _error;
  Object? _pendingResolutionError;
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

  VideoDetailBackProgress? get _backProgress =>
      _arguments[videoDetailBackProgressKey] as VideoDetailBackProgress?;

  VideoDetailEntryOverlayController? get _entryOverlay =>
      _arguments[videoDetailEntryOverlayKey]
          as VideoDetailEntryOverlayController?;

  bool get _usesExternalEntryOverlay => _entryOverlay?.isActive == true;

  bool get _entryExitInProgress =>
      _preparedExitMode == VideoDetailExitMode.entryReverse ||
      _preparedExitMode == VideoDetailExitMode.routeComposite ||
      _preparedExitMode == VideoDetailExitMode.errorFallback;

  bool get _entryReverseInProgress =>
      _preparedExitMode == VideoDetailExitMode.entryReverse;

  bool get _routeCompositeOwnsPresentation =>
      _preparedExitMode == VideoDetailExitMode.routeComposite;

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
      _completeDetailReveal();
    }
  }

  bool get _shouldHoldCoverForPlayer =>
      _hasVideoTransition &&
      !_needsImmediatePipTakeover &&
      // Manual-playback pages have no player frame to wait for. Their first
      // painted detail frame is still gated separately below.
      Pref.autoPlayEnable;

  bool get _playerHandoffCanRelease => videoDetailPlayerHandoffCanRelease(
    playerVisualReady: _initialPlayerVisualReady,
    forceRelease: _playerHandoffForceRelease,
    detailLayoutReady: _initialDetailLayoutReady,
  );

  bool get _entryVisualReady {
    if (!_hasVideoTransition || _needsImmediatePipTakeover) {
      return true;
    }
    return videoDetailEntryCanReveal(
      detailLayoutReady: _initialDetailLayoutReady,
    );
  }

  void _armPlayerHandoffTimeout() {
    _playerHandoffForceReleaseTimer?.cancel();
    final generation = ++_playerHandoffGeneration;
    _playerHandoffForceReleaseTimer = Timer(
      _playerHandoffForceReleaseTimeout,
      () {
        if (!mounted || generation != _playerHandoffGeneration) {
          return;
        }
        _playerHandoffForceReleaseTimer = null;
        // A chained detail navigation can replace the singleton player's
        // launch content before the one-shot layout callback reports. The
        // detail subtree has already been mounted for the full bounded hold,
        // so the timeout must unblock that missing callback as well. Without
        // this fallback an opaque, non-interactive cover can remain above a
        // playable native surface forever.
        setState(() {
          _playerHandoffForceRelease = true;
          _initialDetailLayoutReady = true;
        });
        _scheduleDetailReveal();
        _tryReleasePlayerHandoffCover();
      },
    );
    _tryReleasePlayerHandoffCover();
  }

  void _cancelPlayerHandoffTimeout() {
    _playerHandoffGeneration++;
    _playerHandoffForceReleaseTimer?.cancel();
    _playerHandoffForceReleaseTimer = null;
  }

  void _abortEntryOverlay() {
    // An aborted overlay completes beginReveal's future. Invalidate that
    // continuation before removing it so it cannot clear a replacement local
    // entry layer during a fast exit.
    _entryRevealGeneration++;
    _entryOverlay?.abort();
  }

  void _handleInitialPlayerVisualReady(VideoDetailSession session) {
    if (!mounted ||
        !identical(session, _session) ||
        !session.matchesLaunchContent) {
      return;
    }
    _initialPlayerVisualReady = true;
    _scheduleDetailReveal();
  }

  void _handleInitialDetailLayoutReady(VideoDetailSession session) {
    if (!mounted || !identical(session, _session)) {
      return;
    }
    _initialDetailLayoutReady = true;
    _scheduleDetailReveal();
  }

  void _scheduleDetailReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_showDetail && _showEntryLayer) {
        _beginDetailReveal();
      } else {
        _tryReleasePlayerHandoffCover();
      }
    });
  }

  void _tryReleasePlayerHandoffCover() {
    if (!mounted ||
        !_showPlayerHandoffCover ||
        !_playerHandoffCoverOpaque ||
        _entryExitInProgress ||
        !_revealingDetail ||
        !_playerHandoffCanRelease) {
      return;
    }
    _cancelPlayerHandoffTimeout();
    setState(() => _playerHandoffCoverOpaque = false);
  }

  void _completeDetailReveal() {
    if (!mounted || _entryExitInProgress) {
      return;
    }
    final releasePlayerCover =
        _showPlayerHandoffCover && _playerHandoffCanRelease;
    if (!_showEntryLayer && !releasePlayerCover) {
      return;
    }
    if (releasePlayerCover) {
      _cancelPlayerHandoffTimeout();
    }
    setState(() {
      // The skeleton and player cover change ownership in one frame. The
      // player is already drawable here, so no transparent route background
      // can appear between the two layers.
      _showEntryLayer = false;
      if (releasePlayerCover) {
        _playerHandoffCoverOpaque = false;
      }
    });
  }

  void _handlePlayerHandoffFadeEnd() {
    if (!mounted ||
        !_showPlayerHandoffCover ||
        _playerHandoffCoverOpaque ||
        _entryExitInProgress) {
      return;
    }
    setState(() => _showPlayerHandoffCover = false);
  }

  VideoDetailExitMode _prepareForExit() {
    if (!mounted) {
      return VideoDetailExitMode.detail;
    }
    final preparedExitMode = _preparedExitMode;
    if (preparedExitMode != null) {
      return preparedExitMode;
    }
    if (_error != null) {
      _preparedExitMode = VideoDetailExitMode.errorFallback;
      return VideoDetailExitMode.errorFallback;
    }

    if (_showPlayerHandoffCover) {
      _abortEntryOverlay();
      _detailRevealController.stop();
      _orientationSettleTimer?.cancel();
      _orientationSettleTimer = null;
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      _preparedExitMode = VideoDetailExitMode.routeComposite;
      _preparedExitUsesPlayerHandoff = true;
      setState(() {
        _showDetail = true;
        // Keep a complete, opaque entry scene while a just-mounted detail
        // route reverses. Otherwise the live page can leak through the
        // skeleton's still-fading regions during a fast back action.
        _showEntryLayer = true;
        _useHeroTarget = false;
        _showStaticEntryCover = false;
        _showPlayerHandoffCover = true;
        _playerHandoffCoverOpaque = true;
        _revealingDetail = false;
        _orientationSettling = false;
        _pendingEntryOrientation = null;
        _pendingEntryVariant = null;
        _pendingContentProfile = null;
      });
      return VideoDetailExitMode.routeComposite;
    }

    if (!_showDetail) {
      // While the entry presentation is still authoritative, let the route,
      // Hero, and external overlay reverse along their original animation.
      if (_showEntryLayer && !_revealingDetail && _usesExternalEntryOverlay) {
        setState(() {
          _preparedExitMode = VideoDetailExitMode.entryReverse;
        });
        _entryOverlay?.beginReversibleExit();
        return VideoDetailExitMode.entryReverse;
      }

      // A route without an external overlay still owns a complete skeleton
      // and cover. Keep that composite intact instead of replacing it with a
      // solid surface while the shared geometry returns to the source card.
      if (_showEntryLayer && !_revealingDetail) {
        _preparedExitMode = VideoDetailExitMode.routeComposite;
        setState(() {
          _showStaticEntryCover = _hasVideoTransition;
          _useHeroTarget = false;
        });
        return VideoDetailExitMode.routeComposite;
      }
    }

    _abortEntryOverlay();
    if (!_showDetail) {
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
      _showStaticEntryCover = false;
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
    final preparedExitUsesPlayerHandoff = _preparedExitUsesPlayerHandoff;
    _preparedExitMode = null;
    _preparedExitUsesPlayerHandoff = false;
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
        if (preparedExitUsesPlayerHandoff) {
          setState(() {
            _showStaticEntryCover = false;
            _useHeroTarget = false;
            _showPlayerHandoffCover = true;
            _playerHandoffCoverOpaque = true;
          });
        } else {
          setState(() {
            _showStaticEntryCover = false;
            _useHeroTarget = true;
          });
        }
        _resumeDeferredEntryHandoff();
        break;
      case VideoDetailExitMode.errorFallback:
        _resumeDeferredEntryHandoff();
        break;
      case VideoDetailExitMode.detail:
        if (_showEntryLayer || _useHeroTarget || _showStaticEntryCover) {
          setState(() {
            _showEntryLayer = false;
            _useHeroTarget = false;
            _showStaticEntryCover = false;
          });
        }
        break;
    }
    _tryReleasePlayerHandoffCover();
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
        _useHeroTarget = false;
        if (_fromPip) {
          _showEntryLayer = false;
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
          _useHeroTarget = false;
          if (_fromPip) {
            _showEntryLayer = false;
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
    _initialDetailLayoutReady = false;
    _initialPlayerVisualReady = false;
    _playerHandoffForceRelease = false;
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
        _mountDetailBehindEntry();
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
    _mountDetailBehindEntry();
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginDetailReveal());
  }

  void _mountDetailBehindEntry() {
    final holdCoverForPlayer = _shouldHoldCoverForPlayer;
    setState(() {
      _showDetail = true;
      _useHeroTarget = false;
      _showStaticEntryCover = false;
      _showPlayerHandoffCover = holdCoverForPlayer;
      _playerHandoffCoverOpaque = true;
      _playerHandoffForceRelease = false;
    });
    if (holdCoverForPlayer) {
      _armPlayerHandoffTimeout();
    }
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
        !_entryVisualReady ||
        _revealingDetail) {
      return;
    }
    setState(() {
      // Keep this defensive assignment for sessions mounted before reveal.
      _useHeroTarget = false;
      _showStaticEntryCover = false;
      _revealingDetail = true;
    });
    final entryOverlay = _entryOverlay;
    if (entryOverlay?.isActive == true) {
      final revealGeneration = ++_entryRevealGeneration;
      unawaited(
        entryOverlay!.beginReveal().whenComplete(() {
          if (mounted &&
              revealGeneration == _entryRevealGeneration &&
              identical(entryOverlay, _entryOverlay) &&
              entryOverlay.didCompleteReveal &&
              !_entryExitInProgress &&
              _showEntryLayer) {
            _completeDetailReveal();
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

  void _showResolutionError(Object error) {
    _abortEntryOverlay();
    _cancelPlayerHandoffTimeout();
    setState(() {
      _error = error;
      _showEntryLayer = false;
      _useHeroTarget = false;
      _showStaticEntryCover = false;
      _showPlayerHandoffCover = false;
    });
  }

  VideoDetailEntryLayout _entryLayout(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final pagePadding = Pref.removeSafeArea
        ? EdgeInsets.zero
        : MediaQuery.viewPaddingOf(context);
    return VideoDetailLayoutMetrics.entryLayout(
      viewport,
      isVertical: _entryIsVertical,
      topInset: pagePadding.top,
      pagePadding: pagePadding,
      isPortrait: viewport.height >= viewport.width,
    );
  }

  Widget _entryCoverLayer(
    BuildContext context, {
    required bool enableHero,
    bool animateGeometry = true,
  }) {
    final playerRect = _entryLayout(context).playerRect;
    final cover = _entryCover;
    final coverLayer = cover == null
        ? const ColoredBox(color: Colors.black)
        : NetworkImgLayer(
            key: ValueKey(('video-entry-cover', cover)),
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
          duration: animateGeometry
              ? _orientationTransitionDuration
              : Duration.zero,
          curve: Curves.easeInOutCubic,
          left: playerRect.left,
          top: playerRect.top,
          width: playerRect.width,
          height: playerRect.height,
          child: HeroMode(
            enabled: enableHero,
            child: VideoDetailHero.target(
              key: const ValueKey('video-entry-media-hero'),
              tag: _heroTag,
              backProgress: _backProgress,
              child: coverLayer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _entryMediaHandoffLayer(
    BuildContext context, {
    required bool showHeroTarget,
    required bool showPlayerHandoffCover,
  }) {
    final opacity = showPlayerHandoffCover
        ? (_playerHandoffCoverOpaque ? 1.0 : 0.0)
        : 1.0;
    return AnimatedOpacity(
      key: _entryMediaLayerKey,
      opacity: opacity,
      duration: _entryExitInProgress
          ? Duration.zero
          : _playerHandoffFadeDuration,
      curve: Curves.easeOut,
      onEnd: _handlePlayerHandoffFadeEnd,
      child: _entryCoverLayer(
        context,
        enableHero: showHeroTarget,
        // Keep the same media surface alive while the player settles. The
        // cover owns geometry during that period, so a window/orientation
        // change cannot expose an intermediate black texture.
        animateGeometry: !showPlayerHandoffCover,
      ),
    );
  }

  Widget _entryShell(BuildContext context) {
    final entryLayout = _entryLayout(context);
    return VideoDetailHeroShell.revealing(
      // Keep one shell alive through orientation/profile resolution. Replacing
      // the keyed subtree during the handoff causes the landscape skeleton to
      // jump even when the shared media Rect is unchanged.
      key: const ValueKey('video-detail-entry-shell'),
      progress: _revealingDetail ? _detailRevealController.value : 0,
      isVertical: _entryIsVertical,
      isPortrait: entryLayout.isPortrait,
      playerBottomOverride: entryLayout.playerRect.bottom,
      variant: _skeletonVariant,
      title: _entryTitle,
      expandedIntro: Pref.alwaysExpandIntroPanel,
      showRecommendations: Pref.showRelatedVideo,
      hasSeasonPanel:
          !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasSeasonPanel,
      hasPagesPanel:
          !Pref.alwaysExpandIntroPanel && _entryContentProfile.hasPagesPanel,
      tabCount: _entryContentProfile.tabCount,
      actionCount: _entryContentProfile.actionCount,
      hasEpisodePanel: _entryContentProfile.hasEpisodePanel,
    );
  }

  Widget _animatedEntryShell(BuildContext context) => _entryShell(context);

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

  Widget _errorFallback(BuildContext context, Object error) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: _errorOverlay(context, error),
  );

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _orientationSettleTimer?.cancel();
    _cancelPlayerHandoffTimeout();
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
    if (_error case final error?) {
      return _errorFallback(context, error);
    }
    final showHeroTarget = _useHeroTarget && _hasVideoTransition;
    final showStaticEntryCover =
        _showStaticEntryCover && _showEntryLayer && !showHeroTarget;
    final showPlayerHandoffCover = _showPlayerHandoffCover && !showHeroTarget;
    final hideDetail =
        _hideDetailDuringHeroFlight ||
        _entryReverseInProgress ||
        _routeCompositeOwnsPresentation;
    if (!_showDetail) {
      return Scaffold(
        backgroundColor: showHeroTarget || _externalEntryOwnsPresentation
            ? Colors.transparent
            : colorScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!_externalEntryOwnsPresentation)
              IgnorePointer(child: _animatedEntryShell(context)),
            if (showHeroTarget ||
                showStaticEntryCover ||
                showPlayerHandoffCover)
              IgnorePointer(
                child: _entryMediaHandoffLayer(
                  context,
                  showHeroTarget: showHeroTarget,
                  showPlayerHandoffCover: showPlayerHandoffCover,
                ),
              ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep a deterministic opaque base while the live detail subtree and
        // the entry layers hand ownership to one another.
        ColoredBox(color: colorScheme.surface),
        IgnorePointer(
          ignoring: hideDetail,
          child: Opacity(
            opacity: hideDetail ? 0 : 1,
            child: VideoDetailPageV(
              session: _session,
              onInitialVisualReady: _handleInitialPlayerVisualReady,
              onInitialLayoutReady: _handleInitialDetailLayoutReady,
            ),
          ),
        ),
        if (_showEntryLayer && !_externalEntryOwnsPresentation)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _detailRevealController,
                builder: (context, _) => _animatedEntryShell(context),
              ),
            ),
          ),
        if (showHeroTarget || showStaticEntryCover || showPlayerHandoffCover)
          Positioned.fill(
            child: IgnorePointer(
              child: _entryMediaHandoffLayer(
                context,
                showHeroTarget: showHeroTarget,
                showPlayerHandoffCover: showPlayerHandoffCover,
              ),
            ),
          ),
      ],
    );
  }
}
