import 'dart:async';
import 'dart:convert' show jsonDecode, utf8;
import 'dart:io';
import 'dart:math' show min;
import 'dart:ui';

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/pair.dart';
import 'package:PiliMax/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliMax/grpc/bilibili/community/service/dm/v1.pbenum.dart'
    show SubtitleType;
import 'package:PiliMax/grpc/bilibili/app/listener/v1.pbenum.dart'
    show PlaylistSource;
import 'package:PiliMax/grpc/dm.dart';

import 'package:PiliMax/http/fav.dart';
import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/models/common/list_order.dart';
import 'package:PiliMax/models/common/sponsor_block/action_type.dart';
import 'package:PiliMax/models/common/sponsor_block/post_segment_model.dart';
import 'package:PiliMax/models/common/sponsor_block/segment_model.dart';
import 'package:PiliMax/models/common/sponsor_block/segment_type.dart';
import 'package:PiliMax/models/common/video/audio_quality.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/subtitle_pref_type.dart';
import 'package:PiliMax/models/common/video/video_decode_type.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/models_new/download/playback_meta.dart';
import 'package:PiliMax/models_new/media_list/media_list.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliMax/models_new/sponsor_block/segment_item.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/models_new/video/video_pbp/data.dart';
import 'package:PiliMax/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliMax/models_new/video/video_stein_edgeinfo/data.dart';
import 'package:PiliMax/pages/ai_chat/controller.dart';
import 'package:PiliMax/pages/audio/view.dart';
import 'package:PiliMax/pages/common/publish/publish_route.dart';
import 'package:PiliMax/pages/search/widgets/search_text.dart';
import 'package:PiliMax/pages/sponsor_block/block_mixin.dart';
import 'package:PiliMax/pages/video/download_panel/view.dart';
import 'package:PiliMax/pages/video/introduction/pgc/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/pages/video/medialist/view.dart';
import 'package:PiliMax/pages/video/note/view.dart';
import 'package:PiliMax/pages/video/post_panel/view.dart';
import 'package:PiliMax/pages/video/send_danmaku/view.dart';
import 'package:PiliMax/pages/video/video_detail_args.dart';
import 'package:PiliMax/pages/video/video_media_list_coordinator.dart';
import 'package:PiliMax/pages/video/video_playback_session.dart';
import 'package:PiliMax/pages/video/video_subtitle_coordinator.dart';
import 'package:PiliMax/pages/video/widgets/header_control.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/models/data_source.dart';
import 'package:PiliMax/plugin/pl_player/models/heart_beat_type.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:PiliMax/services/debug_log_service.dart';
import 'package:PiliMax/services/pip_overlay_service.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/connectivity_utils.dart';
import 'package:PiliMax/utils/danmaku_density_trend.dart';
import 'package:PiliMax/utils/extension/context_ext.dart';
import 'package:PiliMax/utils/extension/iterable_ext.dart';
import 'package:PiliMax/utils/extension/nested_scroll_ext.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:PiliMax/utils/video_utils.dart';

import 'package:collection/collection.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart'
    show ExtendedNestedScrollViewState;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart' hide Subtitle;
import 'package:path/path.dart' as path;

final class _MediaKitVideoSubtitlePlayer implements VideoSubtitlePlayer {
  const _MediaKitVideoSubtitlePlayer(this._player);

  final Player _player;

  @override
  Object get identity => _player;

  @override
  Future<void> setPrimarySubtitle(VideoSubtitleTrack? track) =>
      _player.setSubtitleTrack(
        track == null
            ? SubtitleTrack.no()
            : SubtitleTrack(
                track.uri,
                track.label,
                track.language,
                uri: true,
              ),
      );

  @override
  Future<void> setSecondarySubtitle(VideoSubtitleTrack? track) =>
      _player.setSecondarySubtitleTrack(
        track == null
            ? SubtitleTrack.no()
            : SubtitleTrack(
                track.uri,
                track.label,
                track.language,
                uri: true,
              ),
      );
}

class VideoDetailController extends GetxController
    with GetTickerProviderStateMixin, BlockMixin {
  /// 路由传参
  late final Map args;
  late String bvid;
  late int aid;
  late final RxInt cid;
  int? epId;
  int? seasonId;
  int? pgcType;
  late final String heroTag;
  late final RxString cover;

  // 视频类型 默认投稿视频
  late final VideoType videoType;
  @override
  late final isUgc = videoType == VideoType.ugc;
  VideoType? _actualVideoType;

  // 页面来源 稍后再看 收藏夹
  late bool isPlayAll;
  late SourceType sourceType;
  late BiliDownloadEntryInfo entry;
  late bool isFileSource;
  final VideoMediaListCoordinator _mediaListCoordinator =
      VideoMediaListCoordinator();
  VideoMediaListRequest? _activeMediaListRequest;
  Future<void>? _activeMediaListFuture;
  ListOrder get listOrder => _mediaListCoordinator.order;
  RxList<MediaListItemModel> get mediaList => _mediaListCoordinator.items;
  late String watchLaterTitle;

  // 是否正在进入应用内小窗
  bool isEnteringPip = false;

  /// tabs相关配置
  late TabController tabCtr;

  // 请求返回的视频信息
  late PlayUrlModel data;
  final RxBool videoState = false.obs;

  /// 播放器配置 画质 音质 解码格式
  final Rxn<VideoQuality> currentVideoQa = Rxn<VideoQuality>();
  AudioQuality? currentAudioQa;
  late VideoDecodeFormatType currentDecodeFormats;
  final Set<VideoDecodeFormatType> _codecOpenFailedFormats =
      <VideoDecodeFormatType>{};

  // 是否开始自动播放 存在多p的情况下，第二p需要为true
  final RxBool _autoPlay = Pref.autoPlayEnable.obs;

  final videoPlayerKey = GlobalKey();
  final childKey = GlobalKey<ScaffoldState>();

  PlPlayerController plPlayerController = PlPlayerController.getInstance()
    ..brightness.value = -1;
  bool get setSystemBrightness => plPlayerController.setSystemBrightness;
  bool get removeSafeArea => plPlayerController.removeSafeArea;
  double get uiScale => plPlayerController.uiScale;

  late VideoItem firstVideo;
  String? videoUrl;
  String? audioUrl;
  Duration? defaultST;
  Duration? playedTime;
  String get playedTimePos {
    final pos = playedTime?.inMilliseconds;
    return pos == null || pos == 0 ? '' : '?t=${pos / 1000}';
  }

  // 亮度
  double? brightness;

  late final headerCtrKey = GlobalKey<TimeBatteryMixin>();

  Box setting = GStorage.setting;

  // 预设的解码格式
  late List<VideoDecodeFormatType> preferCodecs = Pref.preferCodecs;

  bool get showReply => isFileSource
      ? false
      : isUgc
      ? plPlayerController.showVideoReply
      : plPlayerController.showBangumiReply;

  bool get showRelatedVideo =>
      isFileSource ? false : plPlayerController.showRelatedVideo;

  ScrollController? introScrollCtr;
  ScrollController get effectiveIntroScrollCtr =>
      introScrollCtr ??= ScrollController();

  int? seasonCid;
  late final RxInt seasonIndex = 0.obs;

  PlayerStatus? playerStatus;

  late final scrollKey = GlobalKey<ExtendedNestedScrollViewState>();
  late final RxBool isVertical;
  late final RxDouble scrollRatio = 0.0.obs;

  ScrollController? _scrollCtr;
  ScrollController get scrollCtr => _scrollCtr ??= ScrollController();

  late bool isExpanding = false;
  late bool isCollapsing = false;

  late double minVideoHeight;
  late double maxVideoHeight;
  late double videoHeight;
  late double animHeight;

  AnimationController? animController;
  AnimationController get animationController =>
      animController ??= (AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
      )..addListener(_animListener));

  void refreshPage() {
    scrollKey.currentState?.refresh();
  }

  void _animListener() {
    if (animationController.isForwardOrCompleted) {
      _calcAnimHeight();
      refreshPage();
    }
  }

  void _calcAnimHeight() {
    if (isExpanding) {
      animHeight = clampDouble(
        videoHeight * animationController.value,
        kToolbarHeight,
        videoHeight,
      );
    } else if (isCollapsing) {
      animHeight = clampDouble(
        maxVideoHeight -
            (maxVideoHeight - minVideoHeight) * animationController.value,
        minVideoHeight,
        maxVideoHeight,
      );
    }
  }

  void animToTop() {
    scrollKey.currentState?.animToTop();
  }

  bool _needAnimOnDimensionChanged(bool isVertical) {
    if (isFullScreen) {
      if (PlatformUtils.isMobile) {
        plPlayerController.changeOrientation(isVertical: isVertical);
      }
      return false;
    }
    return true;
  }

  @pragma('vm:notify-debugger-on-exception')
  void _setVideoHeight() {
    try {
      var width = firstVideo.width;
      var height = firstVideo.height;
      if (width == null || height == null) {
        if (isUgc && !isFileSource) {
          final ugcIntroCtr = Get.find<UgcIntroController>(tag: heroTag);
          final cid = this.cid.value;
          final part = ugcIntroCtr.videoDetail.value.pages?.firstWhereOrNull(
            (e) => e.cid == cid,
          );
          if (part != null) {
            final dimension = part.dimension!;
            width = dimension.width!;
            height = dimension.height!;
          } else {
            return;
          }
        } else {
          return;
        }
      }
      final isVertical = height > width;
      if (_scrollCtr?.hasClients != true) {
        videoHeight = isVertical ? maxVideoHeight : minVideoHeight;
        if (this.isVertical.value != isVertical) {
          this.isVertical.value = isVertical;
          _needAnimOnDimensionChanged(isVertical);
        }
        return;
      }
      if (this.isVertical.value != isVertical) {
        this.isVertical.value = isVertical;
        double videoHeight = isVertical ? maxVideoHeight : minVideoHeight;
        if (this.videoHeight != videoHeight) {
          if (videoHeight > this.videoHeight) {
            // current minVideoHeight
            if (_needAnimOnDimensionChanged(isVertical)) {
              isExpanding = true;
              animationController.forward(
                from: (minVideoHeight - scrollCtr.offset) / maxVideoHeight,
              );
            }
            this.videoHeight = maxVideoHeight;
          } else {
            // current maxVideoHeight
            final currentHeight = (maxVideoHeight - scrollCtr.offset)
                .toPrecision(2);
            double minVideoHeightPrecise = minVideoHeight.toPrecision(2);
            if (currentHeight == minVideoHeightPrecise) {
              this.videoHeight = minVideoHeight;
              if (_needAnimOnDimensionChanged(isVertical)) {
                isExpanding = true;
                animationController.forward(from: 1);
              }
            } else if (currentHeight < minVideoHeightPrecise) {
              // expand
              if (_needAnimOnDimensionChanged(isVertical)) {
                isExpanding = true;
                animationController.forward(
                  from: currentHeight / minVideoHeight,
                );
              }
              this.videoHeight = minVideoHeight;
            } else {
              // collapse
              if (_needAnimOnDimensionChanged(isVertical)) {
                isCollapsing = true;
                animationController.forward(
                  from: scrollCtr.offset / (maxVideoHeight - minVideoHeight),
                );
              }
              this.videoHeight = minVideoHeight;
            }
          }
        }
      } else {
        if (scrollCtr.offset != 0) {
          isExpanding = true;
          animationController.forward(from: 1 - scrollCtr.offset / videoHeight);
        }
      }
    } catch (_) {}
  }

  void _updateVerticalStateFromPlayer() {
    try {
      final state = plPlayerController.videoController?.player.state;
      final actualWidth = state?.width;
      final actualHeight = state?.height;
      if (actualWidth == null ||
          actualHeight == null ||
          actualWidth <= 0 ||
          actualHeight <= 0) {
        return;
      }
      final actualIsVertical = actualWidth < actualHeight;
      if (actualIsVertical == isVertical.value) {
        return;
      }
      isVertical.value = actualIsVertical;
      plPlayerController.updateVerticalState(actualIsVertical);
      _setVideoHeight();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_updateVerticalStateFromPlayer error: $e');
      }
    }
  }

  final isLoginVideo = Accounts.get(AccountType.video).isLogin;

  late final watchProgress = GStorage.watchProgress;
  void cacheLocalProgress() {
    if (plPlayerController.playerStatus.isCompleted) {
      watchProgress.put(cid.value.toString(), entry.totalTimeMilli);
    } else if (playedTime case final playedTime?) {
      watchProgress.put(cid.value.toString(), playedTime.inMilliseconds);
    }
  }

  void initFileSource(BiliDownloadEntryInfo entry, {bool isInit = true}) {
    this.entry = entry;
    firstVideo = VideoItem(
      quality: VideoQuality.fromCode(entry.preferedVideoQuality),
      width: entry.ep?.width ?? entry.pageData?.width ?? 1,
      height: entry.ep?.height ?? entry.pageData?.height ?? 1,
    );
    if (watchProgress.get(cid.value.toString()) case final int progress?) {
      if (progress >= entry.totalTimeMilli - 400) {
        defaultST = Duration.zero;
      } else {
        defaultST = Duration(milliseconds: progress);
      }
    } else {
      defaultST = Duration.zero;
    }
    data = PlayUrlModel(timeLength: entry.totalTimeMilli);
    _setVideoHeight();
  }

  /// 注册全屏画质切换回调。
  /// 必须在 onInit 和 didPopNext 中调用，因为 PlPlayerController 是单例，
  /// 新视频页面的 onInit 会覆盖回调为新 controller 的闭包，返回后需重新注册。
  void setupFullScreenQualitySwitch() {
    plPlayerController.onFullScreenChanged = (bool fs) async {
      if (!fs || plPlayerController.isLive) return;
      if (isQuerying) return;
      PlayUrlModel data;
      try {
        data = this.data;
      } catch (_) {
        return;
      }
      if (data.dash == null) return;
      final halfScreenQa = Pref.defaultVideoQaHalfScreen;
      if (halfScreenQa == null) return;
      final isWiFi = await ConnectivityUtils.isWiFi;
      final fsQa = isWiFi ? Pref.defaultVideoQa : Pref.defaultVideoQaCellular;
      final curHighestVideoQa = data.dash!.video!.first.quality.code;
      int targetQa = curHighestVideoQa;
      if (data.acceptQuality?.isNotEmpty == true && fsQa <= curHighestVideoQa) {
        targetQa = data.acceptQuality!.findClosestTarget(
          (e) => e <= fsQa,
          (a, b) => a > b ? a : b,
        );
      }
      // 进入全屏时只升不降，保留用户手动选择的更高画质。
      final curQa = currentVideoQa.value?.code;
      if (curQa != null && targetQa <= curQa) {
        plPlayerController.cacheVideoQa = curQa;
        return;
      }
      plPlayerController.cacheVideoQa = targetQa;
      currentVideoQa.value = VideoQuality.fromCode(targetQa);
      updatePlayer();
    };
  }

  Future<void> persistVideoQa(int quality) async {
    if (plPlayerController.tempPlayerConf) return;

    final String key;
    if (!PlatformUtils.isMobile) {
      key = SettingBoxKey.defaultVideoQa;
    } else if (!plPlayerController.isFullScreen.value &&
        Pref.defaultVideoQaHalfScreen != null) {
      key = SettingBoxKey.defaultVideoQaHalfScreen;
    } else {
      key = await ConnectivityUtils.isWiFi
          ? SettingBoxKey.defaultVideoQa
          : SettingBoxKey.defaultVideoQaCellular;
    }
    await GStorage.setting.put(key, quality);
  }

  @override
  void onInit() {
    super.onInit();
    args = VideoDetailArgs.normalize(Get.arguments);

    // 开启新视频时，如果存在前代播放器的应用内小窗，则按播放上下文决定是否重置旧状态
    // 避免不同视频/分P之间 SponsorBlock 片段状态污染，同时保留同上下文无缝恢复能力
    if (PipOverlayService.isInPipMode) {
      if (kDebugMode) {
        debugPrint(
          '[VideoDetailController] Active PiP detected, closing before new video initialization with context-aware reset',
        );
      }
      PipOverlayService.stopPip(
        immediate: true,
        targetContextKey: PipOverlayService.contextKeyFromArgs(args),
      );
      // 同步清理旧视频的 SponsorBlock 状态，避免污染新视频
      // 不能放在 stopPip 里异步执行，否则会与新视频初始化竞态
      resetBlock();
    }

    videoType = args['videoType'];
    if (videoType == VideoType.pgc) {
      if (!isLoginVideo) {
        _actualVideoType = VideoType.ugc;
      }
    } else if (args['pgcApi'] == true) {
      _actualVideoType = VideoType.pgc;
    }

    bvid = args['bvid'];
    aid = args['aid'];
    cid = RxInt(args['cid']);
    epId = args['epId'];
    seasonId = args['seasonId'];
    pgcType = args['pgcType'];
    heroTag = args['heroTag'];
    cover = RxString(args['cover'] ?? '');
    isVertical = RxBool(args['isVertical'] ?? false);

    sourceType = args['sourceType'] ?? SourceType.normal;
    isFileSource = sourceType == SourceType.file;
    isPlayAll = sourceType != SourceType.normal && !isFileSource;
    if (isFileSource) {
      initFileSource(args['entry']);
    } else if (isPlayAll) {
      watchLaterTitle = args['favTitle'];
      _mediaListCoordinator.setInitialOrder(
        args['desc'] == true ? ListOrder.desc : ListOrder.asc,
      );
      getMediaList();
    }

    tabCtr = TabController(
      length: 2,
      vsync: this,
      initialIndex: Pref.defaultShowComment ? 1 : 0,
    );

    // 进入全屏时切换到全屏默认画质
    if (PlatformUtils.isMobile) {
      setupFullScreenQualitySwitch();
    }
  }

  Future<void> getMediaList({
    bool isReverse = false,
    bool isLoadPrevious = false,
  }) {
    if (isClosed) return Future<void>.value();
    final activeRequest = _activeMediaListRequest;
    final activeFuture = _activeMediaListFuture;
    if (activeRequest != null &&
        activeFuture != null &&
        _mediaListCoordinator.isRequestGenerationCurrent(activeRequest)) {
      if (activeRequest.isReverse == isReverse &&
          activeRequest.isLoadPrevious == isLoadPrevious) {
        return activeFuture;
      }
      return activeFuture.then((_) {
        if (!_mediaListCoordinator.isRequestGenerationCurrent(
          activeRequest,
        )) {
          return Future<void>.value();
        }
        return getMediaList(
          isReverse: isReverse,
          isLoadPrevious: isLoadPrevious,
        );
      });
    }

    final future = _runMediaListChain(
      isReverse: isReverse,
      isLoadPrevious: isLoadPrevious,
      playbackIdentity: _currentPlaybackIdentity(),
    );
    _activeMediaListFuture = future;
    unawaited(
      future.then<void>(
        (_) => _clearActiveMediaListFuture(future),
        onError: (Object _, StackTrace _) =>
            _clearActiveMediaListFuture(future),
      ),
    );
    return future;
  }

  void _clearActiveMediaListFuture(Future<void> future) {
    if (!identical(_activeMediaListFuture, future)) return;
    _activeMediaListFuture = null;
    _activeMediaListRequest = null;
  }

  Future<void> _runMediaListChain({
    required bool isReverse,
    required bool isLoadPrevious,
    required Object playbackIdentity,
  }) async {
    while (!isClosed) {
      final request = _mediaListCoordinator.beginRequest(
        totalCount: args['count'],
        isReverse: isReverse,
        isLoadPrevious: isLoadPrevious,
        playbackIdentity: playbackIdentity,
      );
      if (request == null) return;
      _activeMediaListRequest = request;
      final shouldContinue = await _executeMediaListRequest(
        request: request,
        currentItems: mediaList.toList(growable: false),
        retryAttempt: 0,
      );
      if (!shouldContinue) return;
    }
  }

  Future<bool> _executeMediaListRequest({
    required VideoMediaListRequest request,
    required List<MediaListItemModel> currentItems,
    required int retryAttempt,
  }) async {
    final isShufflePage = request.page != null;
    try {
      final res = await UserHttp.getMediaList(
        type: args['mediaType'] ?? sourceType.mediaType,
        bizId: args['mediaId'] ?? -1,
        ps: 20,
        direction: request.isLoadPrevious,
        pn: request.page,
        oid: isShufflePage
            ? null
            : request.isReverse
            ? null
            : currentItems.isEmpty
            ? args['isContinuePlaying'] == true
                  ? args['oid']
                  : null
            : request.isLoadPrevious
            ? currentItems.first.aid
            : currentItems.last.aid,
        otype: isShufflePage
            ? null
            : request.isReverse
            ? null
            : currentItems.isEmpty
            ? null
            : request.isLoadPrevious
            ? currentItems.first.type
            : currentItems.last.type,
        desc: request.order.isDesc,
        sortField: args['sortField'] ?? 1,
        withCurrent: currentItems.isEmpty && args['isContinuePlaying'] == true,
      );
      if (res case Success(:final response)) {
        if (response.mediaList.isEmpty && retryAttempt < 1) {
          return _retryMediaListRequest(
            request: request,
            currentItems: currentItems,
            retryAttempt: retryAttempt,
          );
        }
        final applyResult = _mediaListCoordinator.applyFetchedItems(
          request: request,
          fetched: response.mediaList,
          currentBvid: bvid,
          currentPlaybackIdentity: _currentPlaybackIdentity(),
        );
        if (!applyResult.accepted) return false;
        if (applyResult.nextEpisode case final nextEpisode?) {
          try {
            Get.find<UgcIntroController>(
              tag: heroTag,
            ).onChangeEpisode(nextEpisode);
          } catch (_) {}
        }
        return response.mediaList.isEmpty && applyResult.hasMoreShufflePages;
      } else if (_mediaListCoordinator.isRequestActive(request)) {
        if (retryAttempt < 1) {
          return _retryMediaListRequest(
            request: request,
            currentItems: currentItems,
            retryAttempt: retryAttempt,
          );
        } else if (_mediaListCoordinator.abandonRequest(request)) {
          res.toast();
        }
      }
    } catch (error, stackTrace) {
      if (_mediaListCoordinator.isRequestActive(request)) {
        Utils.reportError(error, stackTrace);
        if (retryAttempt < 1) {
          return _retryMediaListRequest(
            request: request,
            currentItems: currentItems,
            retryAttempt: retryAttempt,
          );
        } else if (_mediaListCoordinator.abandonRequest(request)) {
          SmartDialog.showToast('播放列表加载失败，请重试');
        }
      }
    }
    return false;
  }

  Future<bool> _retryMediaListRequest({
    required VideoMediaListRequest request,
    required List<MediaListItemModel> currentItems,
    required int retryAttempt,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (isClosed || !_mediaListCoordinator.isRequestActive(request)) {
      return false;
    }
    return _executeMediaListRequest(
      request: request,
      currentItems: currentItems,
      retryAttempt: retryAttempt + 1,
    );
  }

  // 稍后再看面板展开
  void showMediaListPanel(BuildContext context) {
    if (mediaList.isNotEmpty) {
      Widget panel() => MediaListPanel(
        mediaList: mediaList,
        onChangeEpisode: (episode, {bool manual = false}) async {
          try {
            return Get.find<UgcIntroController>(
              tag: heroTag,
            ).onChangeEpisode(episode, manual: manual);
          } catch (_) {}
          return false;
        },
        panelTitle: watchLaterTitle,
        bvid: bvid,
        count: args['count'],
        loadMoreMedia: getMediaList,
        listOrder: listOrder,
        onReverse: () {
          _mediaListCoordinator.advanceOrder(
            totalCount: args['count'],
          );
          getMediaList(isReverse: true);
        },
        loadPrevious: args['isContinuePlaying'] == true
            ? () => getMediaList(isLoadPrevious: true)
            : null,
        onDelete:
            sourceType == SourceType.watchLater ||
                (sourceType == SourceType.fav && args['isOwner'] == true)
            ? (item, index) async {
                if (sourceType == SourceType.watchLater) {
                  final res = await UserHttp.toViewDel(
                    aids: item.aid.toString(),
                  );
                  if (res.isSuccess) {
                    mediaList.removeAt(index);
                  }
                } else {
                  final res = await FavHttp.favVideo(
                    resources: '${item.aid}:${item.type}',
                    delIds: '${args['mediaId']}',
                  );
                  if (res.isSuccess) {
                    mediaList.removeAt(index);
                    SmartDialog.showToast('取消收藏');
                  } else {
                    res.toast();
                  }
                }
              }
            : null,
      );
      if (plPlayerController.isFullScreen.value || showVideoSheet) {
        PageUtils.showVideoBottomSheet(
          context,
          child: plPlayerController.darkVideoPage
              ? Theme(data: ThemeUtils.darkTheme, child: panel())
              : panel(),
        );
      } else {
        childKey.currentState?.showBottomSheet(
          backgroundColor: Colors.transparent,
          constraints: const BoxConstraints(),
          (context) => panel(),
        );
      }
    } else {
      getMediaList();
    }
  }

  bool isPortrait = true;

  bool get horizontalScreen =>
      PlatformUtils.isDesktop || plPlayerController.horizontalScreen;

  bool get showVideoSheet =>
      (!horizontalScreen && !isPortrait) || plPlayerController.isDesktopPip;

  @override
  late final RxString videoLabel = ''.obs;
  @override
  int? get timeLength => data.timeLength;
  @override
  BlockConfigMixin get blockConfig => plPlayerController;
  @override
  Player? get player => plPlayerController.videoPlayerController;
  bool get isCurrentPlayerSource => plPlayerController.isCurrentVideoSource(
    bvid: bvid,
    cid: cid.value,
    sourceOwner: this,
  );
  @override
  bool get isBlockSourceCurrent => isCurrentPlayerSource;
  @override
  bool get isFullScreen => plPlayerController.isFullScreen.value;
  @override
  bool get autoPlay => _autoPlay.value;
  set autoPlay(bool value) => _autoPlay.value = value;
  @override
  bool get preInitPlayer => plPlayerController.preInitPlayer;
  @override
  int get currPosInMilliseconds =>
      defaultST?.inMilliseconds ?? plPlayerController.positionInMilliseconds;
  @override
  Future<void> seekTo(
    Duration duration, {
    required bool isSeek,
    BlockSkipSource skipSource = BlockSkipSource.manual,
  }) => plPlayerController.seekTo(duration, isSeek: isSeek);

  @override
  Widget buildItem(Object item, Animation<double> animation) {
    final theme = ThemeUtils.theme;
    return Align(
      alignment: Alignment.centerLeft,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: GestureDetector(
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              if (details.delta.dx < 0) {
                onRemoveItem(listData.indexOf(item), item);
              }
            },
            child: SearchText(
              bgColor: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.8,
              ),
              textColor: theme.colorScheme.onSecondaryContainer,
              padding: const .symmetric(horizontal: 8, vertical: 4),
              fontSize: 14,
              text: item is SegmentModel
                  ? '跳过: ${item.segmentType.shortTitle}'
                  : '上次看到第${(item as int) + 1}P，点击跳转',
              onTap: (_) {
                if (item is int) {
                  try {
                    UgcIntroController ugcIntroController =
                        Get.find<UgcIntroController>(tag: heroTag);
                    Part part =
                        ugcIntroController.videoDetail.value.pages![item];
                    ugcIntroController.onChangeEpisode(part);
                    SmartDialog.showToast('已跳至第${item + 1}P');
                  } catch (e) {
                    if (kDebugMode) debugPrint('$e');
                    SmartDialog.showToast('跳转失败');
                  }
                  onRemoveItem(listData.indexOf(item), item);
                } else if (item is SegmentModel) {
                  onSkip(item, isSeek: false);
                  onRemoveItem(listData.indexOf(item), item);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  ({int mode, int fontSize, Color color})? dmConfig;
  String? savedDanmaku;

  /// 发送弹幕
  Future<void> showShootDanmakuSheet() async {
    if (plPlayerController.dmState.contains(cid.value)) {
      SmartDialog.showToast('UP主已关闭弹幕');
      return;
    }
    final isPlaying =
        _autoPlay.value && plPlayerController.playerStatus.isPlaying;
    if (isPlaying) {
      await plPlayerController.pause();
    }
    await Get.key.currentState!.push(
      PublishRoute(
        pageBuilder: (buildContext, animation, secondaryAnimation) {
          final child = SendDanmakuPanel(
            cid: cid.value,
            bvid: bvid,
            progress: plPlayerController.positionInMilliseconds,
            initialValue: savedDanmaku,
            onSave: (danmaku) => savedDanmaku = danmaku,
            onSuccess: (danmakuModel) {
              savedDanmaku = null;
              plPlayerController.danmakuController?.addDanmaku(danmakuModel);
            },
            dmConfig: dmConfig,
            onSaveDmConfig: (dmConfig) => this.dmConfig = dmConfig,
          );
          if (plPlayerController.darkVideoPage) {
            return Theme(data: ThemeUtils.darkTheme, child: child);
          }
          return child;
        },
      ),
    );
    if (isPlaying) {
      plPlayerController.play();
    }
  }

  VideoItem findVideoByQa(int qa, {bool setCodecs = false}) {
    /// 根据currentVideoQa和currentDecodeFormats 重新设置videoUrl
    final allVideos = data.dash!.video!;
    final videoList = allVideos.where((i) => i.id == qa).toList();

    if (videoList.isEmpty) {
      final fallback = allVideos.first;
      currentVideoQa.value = VideoQuality.fromCode(fallback.id!);
      return fallback;
    }

    final currentCodes = currentDecodeFormats.codes;
    VideoItem? bestVideo;
    int bestIndex = preferCodecs.length;
    for (final video in videoList) {
      final c = video.codecs!;
      if (currentCodes.any(c.startsWith)) {
        return video;
      }
      for (int i = 0; i < bestIndex; i++) {
        if (preferCodecs[i].codes.any(c.startsWith)) {
          bestIndex = i;
          bestVideo = video;
          break;
        }
      }
    }

    if (setCodecs) {
      if (bestIndex < preferCodecs.length) {
        currentDecodeFormats = preferCodecs[bestIndex];
      } else {
        currentDecodeFormats = VideoDecodeFormatType.fromString(
          videoList.first.codecs!,
        );
      }
    }

    return bestVideo ?? videoList.first;
  }

  void _resetCodecOpenFailures() {
    _codecOpenFailedFormats.clear();
  }

  VideoDecodeFormatType? _formatFromCodecString(String? codecs) {
    if (codecs == null) return null;
    try {
      return VideoDecodeFormatType.fromString(codecs);
    } catch (_) {
      return null;
    }
  }

  List<VideoDecodeFormatType> _codecFallbackOrder(List<VideoItem> videos) {
    final result = <VideoDecodeFormatType>[];
    void add(VideoDecodeFormatType format) {
      if (!result.contains(format)) {
        result.add(format);
      }
    }

    for (final format in preferCodecs) {
      add(format);
    }
    for (final video in videos) {
      if (_formatFromCodecString(video.codecs) case final format?) {
        add(format);
      }
    }
    return result;
  }

  VideoItem? _findCodecOpenFallbackVideo() {
    final qa = currentVideoQa.value?.code;
    if (qa == null) return null;
    final videos = data.dash?.video
        ?.where((i) => i.id == qa || i.quality.code == qa)
        .toList();
    if (videos == null || videos.isEmpty) return null;

    for (final format in _codecFallbackOrder(videos)) {
      if (_codecOpenFailedFormats.contains(format)) {
        continue;
      }
      final video = videos.firstWhereOrNull((i) {
        final codecs = i.codecs;
        return codecs != null && format.codes.any(codecs.startsWith);
      });
      if (video != null) {
        return video;
      }
    }
    return null;
  }

  bool _handleCodecOpenError(String event) {
    if (!Platform.isAndroid ||
        isClosed ||
        isFileSource ||
        plPlayerController.onlyPlayAudio.value) {
      return false;
    }

    _codecOpenFailedFormats.add(currentDecodeFormats);
    final fallbackVideo = _findCodecOpenFallbackVideo();
    if (fallbackVideo == null) {
      return false;
    }

    final fallbackFormat = _formatFromCodecString(fallbackVideo.codecs);
    if (fallbackFormat == null) {
      return false;
    }

    final failedFormat = currentDecodeFormats;
    currentDecodeFormats = fallbackFormat;
    firstVideo = fallbackVideo;
    videoUrl = VideoUtils.getCdnUrl(fallbackVideo.playUrls);
    _setVideoHeight();

    final currentPosition = Duration(
      milliseconds: plPlayerController.positionInMilliseconds,
    );
    final seekToTime = currentPosition > Duration.zero
        ? currentPosition
        : playedTime;
    if (seekToTime != null && seekToTime > Duration.zero) {
      playedTime = seekToTime;
    }
    unawaited(
      DebugLogService.log(
        'video.codec',
        'fallback after codec open error',
        extra: {
          'bvid': bvid,
          'cid': cid.value,
          'event': event,
          'failedFormat': failedFormat.name,
          'fallbackFormat': fallbackFormat.name,
          'seekMs': seekToTime?.inMilliseconds,
        },
      ),
    );

    SmartDialog.showToast(
      '${failedFormat.name} 解码失败，尝试 ${fallbackFormat.name}',
      displayTime: const Duration(milliseconds: 800),
    );
    unawaited(
      playerInit(autoplay: true).catchError((e) {
        if (kDebugMode) {
          debugPrint('codec fallback playerInit failed: $e');
        }
      }),
    );
    return true;
  }

  /// 更新画质、音质
  void updatePlayer() {
    final currentVideoQa = this.currentVideoQa.value;
    if (currentVideoQa == null) return;
    _resetCodecOpenFailures();
    _autoPlay.value = true;
    playedTime = plPlayerController.videoPlayerController?.state.position;
    plPlayerController
      ..isBuffering.value = false
      ..buffered.value = 0;

    firstVideo = findVideoByQa(currentVideoQa.code, setCodecs: true);
    videoUrl = VideoUtils.getCdnUrl(firstVideo.playUrls);

    /// 根据currentAudioQa 重新设置audioUrl
    if (currentAudioQa != null) {
      final firstAudio = data.dash!.audio!.firstWhere(
        (i) => i.id == currentAudioQa!.code,
        orElse: () => data.dash!.audio!.first,
      );
      audioUrl = VideoUtils.getCdnUrl(firstAudio.playUrls, isAudio: true);
    }

    playerInit();
  }

  Future<void>? _initPlayerIfNeeded(
    bool autoFullScreenFlag, {
    bool Function()? isCurrentQuery,
  }) {
    if (_autoPlay.value ||
        (plPlayerController.preInitPlayer && !plPlayerController.processing) &&
            (isFileSource
                ? true
                : videoPlayerKey.currentState?.mounted == true)) {
      return playerInit(
        autoFullScreenFlag: autoFullScreenFlag && _autoPlay.value,
        isCurrentQuery: isCurrentQuery,
      );
    }
    return null;
  }

  Future<void> playerInit({
    bool? autoplay,
    bool autoFullScreenFlag = false,
    bool Function()? isCurrentQuery,
  }) async {
    final initSession = _playbackSession.begin(_currentPlaybackIdentity());
    final requestIdentity = initSession.identity;
    var sourceRequested = false;
    bool isCurrentInit() =>
        _playbackSession.isCurrent(
          initSession,
          isActive: () => !isClosed,
          currentIdentity: _currentPlaybackIdentity,
          additionalValidity: isCurrentQuery,
        ) &&
        (!sourceRequested || plPlayerController.isSourceOwnerActive(this));
    unawaited(
      DebugLogService.log(
        'video.player',
        'init player',
        extra: {
          'bvid': requestIdentity.bvid,
          'cid': requestIdentity.cid,
          'isFileSource': isFileSource,
          'autoplay': autoplay ?? _autoPlay.value,
          'autoFullScreenFlag': autoFullScreenFlag,
          'sourceType': sourceType.name,
        },
      ),
    );
    if (!isCurrentInit()) return;
    // 如果播放器单例已被外部销毁（例如在二级页面关闭了小窗），重新获取一个新实例
    if (plPlayerController.videoPlayerController == null) {
      plPlayerController = PlPlayerController.ensureInstance();
    }
    if (isFileSource) {
      await _loadLocalPlaybackMeta(isCurrent: isCurrentInit);
      if (!isCurrentInit()) return;
    }
    Duration? seek = defaultST ?? playedTime;
    if (seek == null || seek == Duration.zero) {
      seek = getFirstSegment();
    }
    Future<bool> setDataSource() {
      sourceRequested = true;
      return plPlayerController.setDataSource(
        isFileSource
            ? FileSource(
                dir: args['dirPath'],
                typeTag: entry.typeTag!,
                isMp4: entry.mediaType == 1,
                hasDashAudio: entry.hasDashAudio,
              )
            : NetworkSource(
                videoSource: videoUrl!,
                audioSource: audioUrl,
                onCodecOpenError: _handleCodecOpenError,
              ),
        sourceOwner: this,
        seekTo: seek,
        duration: data.timeLength == null
            ? null
            : Duration(milliseconds: data.timeLength!),
        isVertical: isVertical.value,
        aid: requestIdentity.aid,
        bvid: requestIdentity.bvid,
        cid: requestIdentity.cid,
        autoplay: autoplay ?? _autoPlay.value,
        epid: isUgc ? null : requestIdentity.epId,
        seasonId: isUgc ? null : requestIdentity.seasonId,
        pgcType: isUgc ? null : pgcType,
        videoType: videoType,
        onInit: () {
          if (!isCurrentInit()) return;
          videoState.value = true;
          setSubtitle(vttSubtitlesIndex.value);
          if (isFileSource) {
            _updateVerticalStateFromPlayer();
          }
        },
        width: firstVideo.width,
        height: firstVideo.height,
        volume: volume,
        autoFullScreenFlag: autoFullScreenFlag,
      );
    }

    if (!isCurrentInit()) return;
    var sourceApplied = false;
    await _playbackSession.enqueueSourceSwitch(
      initSession,
      isActive: () => !isClosed,
      currentIdentity: _currentPlaybackIdentity,
      additionalValidity: isCurrentQuery,
      action: () async {
        sourceApplied = await setDataSource();
      },
    );
    if (!sourceApplied || !isCurrentInit()) return;

    // 检查 controller 是否已关闭，如果已关闭则跳过后续的资源加载操作
    // （播放信息、弹幕趋势、SponsorBlock 等），避免已销毁的 controller
    // 触发不必要的异步操作和 UI 更新
    if (isClosed) {
      if (kDebugMode) {
        debugPrint(
          '[VideoDetail] playerInit: controller is closed, skipping resource loading',
        );
      }
      return;
    }

    // 需要活跃资源的操作
    if (!isFileSource) {
      if (vttSubtitlesIndex.value == -1) {
        _queryPlayInfo();
      }

      if (plPlayerController.showDmChart && dmTrend.value == null) {
        _getDmTrend();
      }

      if (plPlayerController.enableBlock) {
        initSkip();
      }
    } else {
      if (vttSubtitlesIndex.value == -1) {
        unawaited(_loadFileSubtitles());
      }
    }

    defaultST = null;
  }

  bool isQuerying = false;

  String? _lastQueryBvid;
  int? _lastQueryCid;
  final VideoPlaybackSession _playbackSession = VideoPlaybackSession();
  int _videoUrlQueryGeneration = 0;

  VideoPlaybackIdentity _currentPlaybackIdentity() => VideoPlaybackIdentity(
    aid: aid,
    bvid: bvid,
    cid: cid.value,
    epId: epId,
    seasonId: seasonId,
  );

  bool _isCurrentVideoUrlQuery({
    required int generation,
    required String bvid,
    required int cid,
    required int? epId,
    required int? seasonId,
  }) {
    return !isClosed &&
        generation == _videoUrlQueryGeneration &&
        this.bvid == bvid &&
        this.cid.value == cid &&
        this.epId == epId &&
        this.seasonId == seasonId;
  }

  final languages = Rxn<List<LanguageItem>>();
  final currLang = Rxn<String>();
  void setLanguage(String language) {
    if (currLang.value == language) return;
    if (!isLoginVideo) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    currLang.value = language;
    queryVideoUrl(fromReset: true);
  }

  Volume? volume;

  // 视频链接
  /// TODO: merge [DownloadHttp.getVideoUrl].
  Future<void> queryVideoUrl({
    bool fromReset = false,
    bool reinitializePlayer = true,
    bool autoFullScreenFlag = false,
    bool fromSwitch = false,
    bool Function()? isCurrentSwitch,
  }) async {
    if (isFileSource) {
      if (isCurrentSwitch?.call() == false) return;
      return _initPlayerIfNeeded(
        autoFullScreenFlag,
        isCurrentQuery: isCurrentSwitch,
      );
    }
    if (isQuerying && !fromSwitch) {
      return;
    }
    final queryGeneration = ++_videoUrlQueryGeneration;
    final requestBvid = bvid;
    final requestCid = cid.value;
    final requestEpId = epId;
    final requestSeasonId = seasonId;
    bool isCurrentVideoUrlQuery() => _isCurrentVideoUrlQuery(
      generation: queryGeneration,
      bvid: requestBvid,
      cid: requestCid,
      epId: requestEpId,
      seasonId: requestSeasonId,
    );
    bool isCurrentQuery() =>
        isCurrentVideoUrlQuery() && (isCurrentSwitch?.call() ?? true);
    isQuerying = true;
    try {
      if (_lastQueryBvid != requestBvid || _lastQueryCid != requestCid) {
        // 跨视频/分P时重置画质缓存，确保根据半屏/全屏设置重新选择默认画质。
        // resetTempSettings 在 setDataSource 中执行（HTTP 请求之后），
        // 此处提前重置使得 cacheVideoQa == null 分支能正确初始化。
        if (PlatformUtils.isMobile) {
          plPlayerController.cacheVideoQa = null;
        }
        _lastQueryBvid = requestBvid;
        _lastQueryCid = requestCid;
      }
      if (plPlayerController.enableSponsorBlock && isBlock && !fromReset) {
        unawaited(
          querySponsorBlock(
            bvid: requestBvid,
            cid: requestCid,
            isCurrent: isCurrentQuery,
          ),
        );
      }
      if (plPlayerController.cacheVideoQa == null) {
        final isWiFi = await ConnectivityUtils.isWiFi;
        if (!isCurrentQuery()) return;
        final fsQa = isWiFi ? Pref.defaultVideoQa : Pref.defaultVideoQaCellular;
        final halfScreenQa = Pref.defaultVideoQaHalfScreen;
        plPlayerController
          ..cacheVideoQa =
              !plPlayerController.isFullScreen.value && halfScreenQa != null
              ? min(halfScreenQa, fsQa)
              : fsQa
          ..cacheAudioQa = isWiFi
              ? Pref.defaultAudioQa
              : Pref.defaultAudioQaCellular;
      }

      final result = await VideoHttp.videoUrl(
        cid: requestCid,
        bvid: requestBvid,
        epid: requestEpId,
        seasonId: requestSeasonId,
        tryLook: plPlayerController.tryLook,
        videoType: _actualVideoType ?? videoType,
        language: currLang.value,
        voiceBalance: plPlayerController.enableAudioNormalization,
      );
      if (!isCurrentQuery()) return;

      if (result case Success(:final response)) {
        data = response;

        languages.value = data.language?.items;
        currLang.value = data.curLanguage;

        volume = data.volume;

        if (!fromReset) {
          final progress = args.remove('progress');
          final playUrlStartTime = defaultST == null
              ? _resolvePlayUrlStartTime(
                  lastPlayTime: data.lastPlayTime,
                  lastPlayCid: data.lastPlayCid,
                )
              : null;
          if (_isTrustedRouteProgress(progress)) {
            defaultST = Duration(milliseconds: progress);
          } else if (playUrlStartTime != null) {
            defaultST = playUrlStartTime;
          }
        }

        if (!isUgc && !fromReset && plPlayerController.enablePgcSkip) {
          if (data.clipInfoList case final clipInfoList?) {
            resetBlock();
            unawaited(
              handleSBData(clipInfoList, isCurrent: isCurrentQuery),
            );
          }
        }

        if (data.acceptDesc?.contains('试看') == true) {
          SmartDialog.showToast(
            '该视频为专属视频，仅提供试看',
            displayTime: const Duration(seconds: 3),
          );
        }
        if (data.dash == null && data.durl?.isNotEmpty == true) {
          final durl = data.durl!;
          if (durl.length > 1) {
            final sb = StringBuffer('edl://!no_clip;!no_chapters;');
            for (final segment in durl) {
              final video = VideoUtils.getCdnUrl(segment.playUrls);
              sb.write('%${utf8.encode(video).length}%$video');
              if (segment.length case final length?) {
                sb.write(',length=${length / 1000}');
              }
              sb.write(';');
            }
            videoUrl = sb.toString();
          } else {
            videoUrl = VideoUtils.getCdnUrl(durl.single.playUrls);
          }
          audioUrl = '';

          // 实际为FLV/MP4格式，但已被淘汰，这里仅做兜底处理
          final videoQuality = VideoQuality.fromCode(data.quality!);
          firstVideo = VideoItem(
            id: data.quality!,
            baseUrl: videoUrl,
            codecs: 'avc1',
            quality: videoQuality,
          );
          _setVideoHeight();
          currentDecodeFormats = VideoDecodeFormatType.AVC;
          currentVideoQa.value = videoQuality;
          if (reinitializePlayer) {
            await _initPlayerIfNeeded(
              autoFullScreenFlag,
              isCurrentQuery: isCurrentQuery,
            );
            if (!isCurrentQuery()) return;
          } else {
            // 从 PiP 返回时，重新初始化 SponsorBlock
            if (plPlayerController.enableSponsorBlock &&
                segmentList.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (isCurrentQuery()) {
                  initSkip();
                }
              });
            }
          }
          if (isCurrentQuery()) {
            isQuerying = false;
          }
          return;
        }
        if (data.dash == null) {
          SmartDialog.showToast('视频资源不存在');
          _autoPlay.value = false;
          videoState.value = false;
          if (plPlayerController.isFullScreen.value) {
            plPlayerController.triggerFullScreen(status: false);
          }
          isQuerying = false;
          return;
        }
        final List<VideoItem> videoList = data.dash!.video!;
        // if (kDebugMode) debugPrint("allVideosList:${allVideosList}");
        // 当前可播放的最高质量视频
        final curHighestVideoQa = videoList.first.quality.code;
        // 预设的画质为null，则当前可用的最高质量
        int targetVideoQa = curHighestVideoQa;
        if (data.acceptQuality?.isNotEmpty == true &&
            plPlayerController.cacheVideoQa! <= curHighestVideoQa) {
          // 如果预设的画质低于当前最高
          targetVideoQa = data.acceptQuality!.findClosestTarget(
            (e) => e <= plPlayerController.cacheVideoQa!,
            (a, b) => a > b ? a : b,
          );
        }
        currentVideoQa.value = VideoQuality.fromCode(targetVideoQa);

        /// 优先顺序 设置中指定解码格式 -> 当前可选的首个解码格式
        final supportFormats = data.supportFormats!;
        _resetCodecOpenFailures();

        // 根据画质选编码格式
        currentDecodeFormats = VideoUtils.selectCodec(
          supportFormats
              .firstWhere(
                (e) => e.quality == targetVideoQa,
                orElse: () => supportFormats.first,
              )
              .codecs!,
          preferCodecs,
        );

        /// 取出符合当前画质的videoList
        final videosList = videoList
            .where((e) => e.quality.code == targetVideoQa)
            .toList();

        /// 取出符合当前解码格式的videoItem
        firstVideo = videosList.firstWhere(
          (e) => currentDecodeFormats.codes.any(e.codecs!.startsWith),
          orElse: () => videosList.first,
        );
        _setVideoHeight();

        videoUrl = VideoUtils.getCdnUrl(firstVideo.playUrls);

        /// 优先顺序 设置中指定质量 -> 当前可选的最高质量
        AudioItem? firstAudio;
        final audioList = data.dash?.audio;
        if (audioList != null && audioList.isNotEmpty) {
          final List<int> audioIds = audioList.map((map) => map.id!).toList();
          int closestNumber = audioIds.findClosestTarget(
            (e) => e <= plPlayerController.cacheAudioQa,
            (a, b) => a > b ? a : b,
          );
          if (!audioIds.contains(plPlayerController.cacheAudioQa) &&
              audioIds.any((e) => e > plPlayerController.cacheAudioQa)) {
            closestNumber = AudioQuality.k192.code;
          }
          firstAudio = audioList.firstWhere(
            (e) => e.id == closestNumber,
            orElse: () => audioList.first,
          );
          audioUrl = VideoUtils.getCdnUrl(firstAudio.playUrls, isAudio: true);
          if (firstAudio.id case final int id?) {
            currentAudioQa = AudioQuality.fromCode(id);
          }
        } else {
          audioUrl = '';
        }
        if (reinitializePlayer) {
          await _initPlayerIfNeeded(
            autoFullScreenFlag,
            isCurrentQuery: isCurrentQuery,
          );
          if (!isCurrentQuery()) return;
        } else {
          // 从 PiP 返回时，播放器已在运行，但需要重新初始化 SponsorBlock 的跳过监听器
          if (plPlayerController.enableSponsorBlock && segmentList.isNotEmpty) {
            // 等待播放器就绪
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (isCurrentQuery()) {
                initSkip();
              }
            });
          }
        }
      } else {
        _autoPlay.value = false;
        videoState.value = false;
        if (plPlayerController.isFullScreen.value) {
          plPlayerController.triggerFullScreen(status: false);
        }
        result.toast();
      }
    } finally {
      if (isCurrentVideoUrlQuery()) {
        isQuerying = false;
      }
    }
  }

  late final List<PostSegmentModel> postList = <PostSegmentModel>[];
  void onBlock(BuildContext context) {
    if (postList.isEmpty) {
      postList.add(
        PostSegmentModel(
          segment: Pair(
            first: 0,
            second: plPlayerController.positionInMilliseconds / 1000,
          ),
          category: SegmentType.sponsor,
          actionType: ActionType.skip,
        ),
      );
    }
    if (plPlayerController.isFullScreen.value || showVideoSheet) {
      final child = PostPanel(
        enableSlide: false,
        videoDetailController: this,
        plPlayerController: plPlayerController,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: plPlayerController.darkVideoPage
            ? Theme(data: ThemeUtils.darkTheme, child: child)
            : child,
      );
    } else {
      childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(),
        (context) => PostPanel(
          videoDetailController: this,
          plPlayerController: plPlayerController,
        ),
      );
    }
  }

  RxList<Subtitle> subtitles = RxList<Subtitle>();
  final Map<int, VideoSubtitleSource> vttSubtitles = {};

  late final RxInt vttSubtitlesIndex = (-1).obs;
  late final RxInt vttSecondarySubtitlesIndex = 0.obs;
  int _playInfoQueryGeneration = 0;
  late final VideoSubtitleCoordinator _subtitleCoordinator =
      VideoSubtitleCoordinator(
        subtitles: () => subtitles,
        sources: vttSubtitles,
        primaryIndex: () => vttSubtitlesIndex.value,
        setPrimaryIndex: (value) => vttSubtitlesIndex.value = value,
        secondaryIndex: () => vttSecondarySubtitlesIndex.value,
        setSecondaryIndex: (value) => vttSecondarySubtitlesIndex.value = value,
        currentContext: () => VideoSubtitleContext(
          bvid: bvid,
          cid: cid.value,
          epId: epId,
          seasonId: seasonId,
        ),
        isCurrentSource: () => !isClosed && isCurrentPlayerSource,
        playerProvider: () {
          final player = plPlayerController.videoPlayerController;
          return player == null ? null : _MediaKitVideoSubtitlePlayer(player);
        },
        loadVtt: VideoHttp.vttSubtitles,
      );

  void _invalidateSubtitleSelections() => _subtitleCoordinator.invalidate();

  bool _isCurrentPlayInfoQuery({
    required int generation,
    required String bvid,
    required int cid,
    required int? epId,
    required int? seasonId,
  }) =>
      generation == _playInfoQueryGeneration &&
      !isClosed &&
      isCurrentPlayerSource &&
      bvid == this.bvid &&
      cid == this.cid.value &&
      epId == this.epId &&
      seasonId == this.seasonId;

  late final RxBool showVP = Pref.showViewPointsOverlay.obs;
  late final RxList<ViewPointSegment> viewPointList = <ViewPointSegment>[].obs;

  ({List<SegmentItemModel> items, bool useBlockConfig, bool isBlockSource})?
  _resolveLocalSkipSegments(DownloadPlaybackMeta meta) {
    final clipInfo = meta.clipInfo;
    if (entry.ep != null &&
        plPlayerController.enablePgcSkip &&
        clipInfo != null &&
        clipInfo.items.isNotEmpty) {
      return (
        items: clipInfo.toSegmentItemModels(),
        useBlockConfig: false,
        isBlockSource: false,
      );
    }
    final sponsorBlock = meta.sponsorBlock;
    if (plPlayerController.enableSponsorBlock &&
        sponsorBlock != null &&
        sponsorBlock.items.isNotEmpty) {
      return (
        items: sponsorBlock.toSegmentItemModels(),
        useBlockConfig: true,
        isBlockSource: true,
      );
    }
    return null;
  }

  Future<void> _loadLocalPlaybackMeta({bool Function()? isCurrent}) async {
    bool canApply() => !isClosed && (isCurrent?.call() ?? true);
    if (!canApply()) return;
    viewPointList.clear();
    resetBlock();
    final metaFile = File(
      path.join(entry.entryDirPath, PathUtils.playbackMetaName),
    );
    if (!metaFile.existsSync()) {
      return;
    }
    try {
      final metaJson = await metaFile.readAsString();
      if (!canApply()) return;
      final meta = DownloadPlaybackMeta.fromJson(
        (jsonDecode(metaJson) as Map).cast<String, dynamic>(),
      );
      final durationMs = data.timeLength ?? entry.totalTimeMilli;
      final chapters = meta.chapters;
      if (plPlayerController.showViewPoints &&
          durationMs > 0 &&
          chapters != null) {
        viewPointList.assignAll(
          chapters.items.where((item) => item.toMs != null).map((item) {
            final toMs = item.toMs!;
            return ViewPointSegment(
              end: (toMs / durationMs).clamp(0.0, 1.0),
              title: item.content,
              url: item.imgUrl,
              from: item.fromMs == null ? null : item.fromMs! ~/ 1000,
              to: toMs ~/ 1000,
            );
          }).toList(),
        );
      }
      if (_resolveLocalSkipSegments(meta) case final resolved?) {
        await handleSBData(resolved.items, isCurrent: canApply);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('load local playback meta failed: $e');
      }
    }
  }

  Future<void> _loadFileSubtitles() async {
    _playInfoQueryGeneration++;
    _invalidateSubtitleSelections();
    final context = _subtitleCoordinator.captureContext();
    bool isCurrentContext() => _subtitleCoordinator.isCurrentContext(context);

    await setSubtitle(0);
    if (!isCurrentContext()) return;
    // Local playback must not inherit mpv's secondary-sid from the last video.
    await setSecondarySubtitle(0);
    if (!isCurrentContext()) return;
    final indexFile = File(
      path.join(
        entry.entryDirPath,
        PathUtils.subtitlesDirName,
        PathUtils.subtitleIndexName,
      ),
    );
    if (!indexFile.existsSync()) return;

    List<Subtitle> loaded;
    try {
      final jsonList = (jsonDecode(await indexFile.readAsString()) as List)
          .cast<Map<String, dynamic>>();
      if (!isCurrentContext()) return;
      loaded = jsonList.map(Subtitle.fromJson).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('_loadFileSubtitles parse failed: $e');
      return;
    }

    final validSubs = <Subtitle>[];
    for (final sub in loaded) {
      final vttPath = path.join(
        entry.entryDirPath,
        PathUtils.subtitlesDirName,
        PathUtils.subtitleVttName(sub.lan),
      );
      if (File(vttPath).existsSync()) {
        vttSubtitles[validSubs.length] = (isData: false, id: vttPath);
        validSubs.add(sub);
      }
    }
    if (validSubs.isEmpty) return;
    if (!isCurrentContext()) return;

    final preference = Pref.subtitlePreferenceV2;
    var isMuted = false;
    if (preference == SubtitlePrefType.auto && PlatformUtils.isMobile) {
      isMuted = (await FlutterVolumeController.getVolume() ?? 0.0) <= 0.0;
      if (!isCurrentContext()) return;
    }
    final idx = switch (preference) {
      SubtitlePrefType.off => 0,
      SubtitlePrefType.on => 1,
      SubtitlePrefType.withoutAi =>
        validSubs.first.lan.startsWith('ai') ? 0 : 1,
      SubtitlePrefType.auto =>
        !validSubs.first.lan.startsWith('ai') || isMuted ? 1 : 0,
    };
    if (!isCurrentContext()) return;
    subtitles.value = validSubs;
    await setSubtitle(idx);
  }

  // 设定字幕轨道
  Future<void> setSubtitle(int index) =>
      _subtitleCoordinator.selectPrimary(index);

  Future<void> setSecondarySubtitle(int index) =>
      _subtitleCoordinator.selectSecondary(index);

  // interactive video
  int? graphVersion;
  EdgeInfoData? steinEdgeInfo;
  late final RxBool showSteinEdgeInfo = false.obs;
  int _steinEdgeQueryGeneration = 0;

  Future<void> getSteinEdgeInfo([int? edgeId]) async {
    final queryGeneration = ++_steinEdgeQueryGeneration;
    final requestBvid = bvid;
    final requestGraphVersion = graphVersion;
    bool isCurrentQuery() =>
        !isClosed &&
        queryGeneration == _steinEdgeQueryGeneration &&
        requestBvid == bvid &&
        requestGraphVersion == graphVersion;
    steinEdgeInfo = null;
    try {
      final res = await Request().get(
        '/x/stein/edgeinfo_v2',
        queryParameters: {
          'bvid': requestBvid,
          'graph_version': requestGraphVersion,
          'edge_id': ?edgeId,
        },
      );
      if (!isCurrentQuery()) return;
      if (res.data['code'] == 0) {
        steinEdgeInfo = EdgeInfoData.fromJson(res.data['data']);
      } else {
        if (kDebugMode) {
          debugPrint('getSteinEdgeInfo error: ${res.data['message']}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('getSteinEdgeInfo: $e');
    }
  }

  late bool continuePlayingPart = Pref.continuePlayingPart;

  Duration? _resolvePlayUrlStartTime({
    required int lastPlayTime,
    required int? lastPlayCid,
  }) {
    if (lastPlayTime <= 0) {
      return Duration.zero;
    }
    return _canUseLastPlayTime(lastPlayCid)
        ? Duration(milliseconds: lastPlayTime)
        : Duration.zero;
  }

  bool _isTrustedRouteProgress(dynamic progress) {
    if (progress is! int) return false;

    final progressAid = args.remove('progressAid');
    final progressBvid = args.remove('progressBvid');
    final progressCid = args.remove('progressCid');
    final hasIdentity =
        progressAid != null || progressBvid != null || progressCid != null;
    if (!hasIdentity) return false;

    return (progressAid == null || progressAid == aid) &&
        (progressBvid == null || progressBvid == bvid) &&
        (progressCid == null || progressCid == cid.value);
  }

  bool _canUseLastPlayTime(int? lastPlayCid) {
    if (lastPlayCid != null && lastPlayCid != 0) {
      return lastPlayCid == cid.value;
    }
    // PGC/PUGV progress can come from watch_progress without last_play_cid.
    return (_actualVideoType ?? videoType) != VideoType.ugc;
  }

  Future<void> _queryPlayInfo() async {
    final queryGeneration = ++_playInfoQueryGeneration;
    _invalidateSubtitleSelections();
    final requestAid = aid;
    final requestBvid = bvid;
    final requestCid = cid.value;
    final requestEpId = epId;
    final requestSeasonId = seasonId;
    final requestTimeLength = data.timeLength;
    bool isCurrentQuery() => _isCurrentPlayInfoQuery(
      generation: queryGeneration,
      bvid: requestBvid,
      cid: requestCid,
      epId: requestEpId,
      seasonId: requestSeasonId,
    );

    vttSubtitles.clear();
    await setSubtitle(0);
    if (!isCurrentQuery()) return;
    // Do not carry a secondary track across parts or videos. Clearing the
    // mpv option also prevents stale track ids from colliding with sub-add.
    await setSecondarySubtitle(0);
    if (!isCurrentQuery()) return;
    if (plPlayerController.showViewPoints) {
      viewPointList.clear();
    }
    final res = await VideoHttp.playInfo(
      bvid: requestBvid,
      cid: requestCid,
      seasonId: requestSeasonId,
      epId: requestEpId,
    );
    if (!isCurrentQuery()) return;
    if (res case Success(:final response)) {
      if (response.lastPlayTime != null &&
          response.lastPlayTime! > 0 &&
          _canUseLastPlayTime(response.lastPlayCid)) {
        if (Accounts.get(AccountType.video).mid !=
            Accounts.get(AccountType.heartbeat).mid) {
          if (plPlayerController.position.value <= 3) {
            plPlayerController.seekTo(
              Duration(milliseconds: response.lastPlayTime!),
            );
            SmartDialog.showToast('已跳转至上次观看位置');
          }
        }
      }

      // interactive video
      late final introCtr = Get.find<UgcIntroController>(tag: heroTag);
      if (isUgc && graphVersion == null) {
        try {
          if (introCtr.videoDetail.value.rights?.isSteinGate == 1) {
            graphVersion = response.interaction?.graphVersion;
            getSteinEdgeInfo();
          }
        } catch (e) {
          if (kDebugMode) debugPrint('handle stein: $e');
        }
      }

      if (isUgc && continuePlayingPart) {
        continuePlayingPart = false;
        final lastCid = response.lastPlayCid;
        if (lastCid != null && lastCid != 0 && lastCid != cid.value) {
          try {
            final pages = introCtr.videoDetail.value.pages;
            if (pages != null && pages.length > 1) {
              final index = pages.indexWhere((item) => item.cid == lastCid);
              if (index != -1) {
                onAddItem(index);
              }
            }
          } catch (_) {}
        }
      }
      if (!isCurrentQuery()) return;

      if (plPlayerController.showViewPoints &&
          response.viewPoints?.firstOrNull?.type == 2) {
        try {
          viewPointList.value = response.viewPoints!.map((item) {
            final end = (item.to! / (requestTimeLength! / 1000)).clamp(
              0.0,
              1.0,
            );
            return ViewPointSegment(
              end: end,
              title: item.content,
              url: item.imgUrl,
              from: item.from,
              to: item.to,
            );
          }).toList();
        } catch (_) {}
      }

      if (response.subtitle?.subtitles case final sub? when (sub.isNotEmpty)) {
        await _setSubtitle(sub, isCurrent: isCurrentQuery);
        if (!isCurrentQuery()) return;
      } else if (!Accounts.main.isLogin) {
        final res = await DmGrpc.dmView(requestAid, requestCid);
        if (!isCurrentQuery()) return;
        if (res case Success(:final response)) {
          if (response.hasSubtitle() &&
              response.subtitle.subtitles.isNotEmpty) {
            await _setSubtitle(
              response.subtitle.subtitles
                  .map(
                    (i) => Subtitle(
                      lan: i.lan,
                      lanDoc: i.lanDoc,
                      subtitleUrl: i.subtitleUrl.replaceFirst(
                        RegExp('^https?:'),
                        '',
                      ),
                      isAi: i.type == SubtitleType.AI,
                    ),
                  )
                  .toList()
                ..sort(),
              isCurrent: isCurrentQuery,
            );
            if (!isCurrentQuery()) return;
          }
        } else {
          res.toast();
        }
      }
    }
  }

  Future<void> _setSubtitle(
    List<Subtitle> sub, {
    required bool Function() isCurrent,
  }) async {
    var isMuted = false;
    if (Pref.subtitlePreferenceV2 == .auto && PlatformUtils.isMobile) {
      isMuted = (await FlutterVolumeController.getVolume() ?? 0.0) <= 0.0;
      if (!isCurrent()) return;
    }

    final idx = switch (Pref.subtitlePreferenceV2) {
      .off => 0,
      .on => 1,
      .withoutAi => sub.first.lan.startsWith('ai') ? 0 : 1,
      .auto => !sub.first.lan.startsWith('ai') || isMuted ? 1 : 0,
    };
    if (!isCurrent()) return;
    subtitles.value = sub;
    await setSubtitle(idx);
  }

  void updateMediaListHistory(int aid) {
    if (args['sortField'] != null) {
      VideoHttp.medialistHistory(
        desc: listOrder.isDesc ? 1 : 0,
        oid: aid,
        upperMid: args['mediaId'],
      );
    }
  }

  void syncCompletedProgressForCurrentVideo({Duration? fallbackDuration}) {
    if (sourceType == SourceType.normal) return;
    final currentDuration = VideoMediaListCoordinator.resolveDurationSeconds(
      timeLengthMilliseconds: data.timeLength,
      fallbackDuration: fallbackDuration,
    );
    _mediaListCoordinator.updateProgress(
      videoAid: aid,
      videoBvid: bvid,
      videoCid: cid.value,
      progressSeconds: -1,
      videoDuration: currentDuration,
    );
  }

  void makeHeartBeat() {
    if (plPlayerController.enableHeart &&
        !plPlayerController.playerStatus.isCompleted &&
        playedTime != null) {
      try {
        final progressSeconds =
            VideoMediaListCoordinator.heartBeatProgressSeconds(
              position: playedTime!,
              isCompleted: plPlayerController.playerStatus.isCompleted,
              timeLengthMilliseconds: data.timeLength,
            );
        plPlayerController.makeHeartBeat(
          progressSeconds,
          type: HeartBeatType.completed,
          isManual: true,
          aid: aid,
          bvid: bvid,
          cid: cid.value,
          epid: isUgc ? null : epId,
          seasonId: isUgc ? null : seasonId,
          pgcType: isUgc ? null : pgcType,
          videoType: videoType,
        );
        if (sourceType != SourceType.normal) {
          _mediaListCoordinator.updateProgress(
            videoAid: aid,
            videoBvid: bvid,
            videoCid: cid.value,
            progressSeconds: plPlayerController.playerStatus.isCompleted
                ? -1
                : playedTime!.inSeconds,
            videoDuration: VideoMediaListCoordinator.resolveDurationSeconds(
              timeLengthMilliseconds: data.timeLength,
              fallbackDuration: playedTime,
            ),
          );
        }
      } catch (_) {}
    }
  }

  @override
  void onClose() {
    if (isEnteringPip) {
      // 正在进入小窗，保留资源
      return;
    }
    // 页面 pop 后 GetX 才延迟触发 onClose，此时播放器单例可能已被下层视频页
    // 重新接管（didPopNext -> playerInit 恢复播放）；仅当单例仍持有本页内容时
    // 才暂停，否则会与下层页面的恢复播放竞速
    if (isCurrentPlayerSource) {
      plPlayerController.pause();
    }
    cancelBlockListener();
    _dmTrendTaskId++;
    _mediaListCoordinator.invalidate();
    _playbackSession.invalidate();
    _steinEdgeQueryGeneration++;
    cid.close();
    if (isFileSource) {
      cacheLocalProgress();
    }
    introScrollCtr?.dispose();
    introScrollCtr = null;
    _scrollCtr?.dispose();
    animController
      ?..removeListener(_animListener)
      ..dispose();
    _playInfoQueryGeneration++;
    _invalidateSubtitleSelections();
    vttSecondarySubtitlesIndex.value = 0;
    subtitles.clear();
    vttSubtitles.clear();
    Get.delete<AiChatController>(tag: heroTag);
    super.onClose();
  }

  void onReset({bool isStein = false}) {
    if (isFileSource) {
      cacheLocalProgress();
    }

    playedTime = null;
    _dmTrendTaskId++;
    _playbackSession.invalidate();
    _steinEdgeQueryGeneration++;
    defaultST = null;
    videoUrl = null;
    audioUrl = null;
    _resetCodecOpenFailures();

    // danmaku
    savedDanmaku = null;

    // subtitle
    _playInfoQueryGeneration++;
    _invalidateSubtitleSelections();
    subtitles.clear();
    vttSubtitlesIndex.value = -1;
    vttSecondarySubtitlesIndex.value = 0;
    vttSubtitles.clear();

    if (plPlayerController.showViewPoints) {
      viewPointList.clear();
    }
    if (!PipOverlayService.isInPipMode) {
      resetBlock();
    }

    if (!isFileSource) {
      // language
      languages.value = null;
      currLang.value = null;

      // dm trend
      if (plPlayerController.showDmChart) {
        dmTrend.value = null;
      }

      // interactive video
      if (!isStein) {
        graphVersion = null;
      }
      steinEdgeInfo = null;
      showSteinEdgeInfo.value = false;
    }
  }

  late final Rx<LoadingState<List<double>>?> dmTrend =
      Rx<LoadingState<List<double>>?>(null);
  late final RxBool showDmTrendChart = true.obs;
  int _dmTrendTaskId = 0;

  Future<void> _getDmTrend() async {
    final source = plPlayerController.dmChartSource;
    if (!source.isEnabled) {
      dmTrend.value = null;
      return;
    }

    final taskId = ++_dmTrendTaskId;
    bool shouldCancel() => taskId != _dmTrendTaskId || isClosed;

    dmTrend.value = LoadingState<List<double>>.loading();

    if (source.enableOfficial) {
      final official = await _tryGetOfficialDmTrend();
      if (shouldCancel()) return;
      if (official?.isNotEmpty == true) {
        dmTrend.value = Success(official!);
        return;
      }
      if (!source.enableLocalDensity) {
        dmTrend.value = const Error(null);
        return;
      }
    }

    if (source.enableLocalDensity) {
      final local = await _tryBuildLocalDmTrend(shouldCancel);
      if (shouldCancel()) return;
      if (local?.isNotEmpty == true) {
        dmTrend.value = Success(local!);
        return;
      }
    }

    dmTrend.value = const Error(null);
  }

  Future<List<double>?> _tryGetOfficialDmTrend() async {
    try {
      final res = await Request().get(
        'https://bvc.bilivideo.com/pbp/data',
        queryParameters: {'bvid': bvid, 'cid': cid.value},
      );
      PbpData data = PbpData.fromJson(res.data);
      int stepSec = data.stepSec ?? 0;
      if (stepSec != 0 && data.events?.eDefault?.isNotEmpty == true) {
        return data.events!.eDefault!;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('_tryGetOfficialDmTrend: $e');
    }
    return null;
  }

  Future<List<double>?> _tryBuildLocalDmTrend(
    bool Function() shouldCancel,
  ) async {
    try {
      final durationMs =
          data.timeLength ?? plPlayerController.durationInMilliseconds;
      return await DanmakuDensityTrend.build(
        cid: cid.value,
        durationMs: durationMs,
        shouldCancel: shouldCancel,
      );
    } catch (e, s) {
      if (kDebugMode) debugPrint('_tryBuildLocalDmTrend: $e');
      Utils.reportError(e, s);
      return null;
    }
  }

  void showNoteList(BuildContext context) {
    String? title;
    try {
      title = Get.find<UgcIntroController>(
        tag: heroTag,
      ).videoDetail.value.title;
    } catch (_) {}
    if (plPlayerController.isFullScreen.value || showVideoSheet) {
      final child = NoteListPage(
        oid: aid,
        enableSlide: false,
        heroTag: heroTag,
        isStein: graphVersion != null,
        title: title,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: plPlayerController.darkVideoPage
            ? Theme(data: ThemeUtils.darkTheme, child: child)
            : child,
      );
    } else {
      childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(),
        (context) => NoteListPage(
          oid: aid,
          heroTag: heroTag,
          isStein: graphVersion != null,
          title: title,
        ),
      );
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  bool onSkipSegment() {
    try {
      if (plPlayerController.enableBlock) {
        if (listData.lastOrNull case final SegmentModel item) {
          onSkip(item, isSeek: false);
          onRemoveItem(listData.indexOf(item), item);
          return true;
        }
      }
    } catch (e, s) {
      Utils.reportError(e, s);
    }
    return false;
  }

  void toAudioPage() {
    int? id;
    int? extraId;
    PlaylistSource from = PlaylistSource.UP_ARCHIVE;
    if (isPlayAll) {
      id = args['mediaId'];
      extraId = sourceType.extraId;
      from = sourceType.playlistSource!;
    } else if (isUgc) {
      try {
        final ctr = Get.find<UgcIntroController>(tag: heroTag);
        id = ctr.videoDetail.value.ugcSeason?.id;
        if (id != null) {
          extraId = 8;
          from = PlaylistSource.MEDIA_LIST;
        }
      } catch (_) {}
    }
    AudioPage.toAudioPage(
      itemType: 1,
      id: id,
      oid: aid,
      subId: [cid.value],
      from: from,
      heroTag: heroTag,
      start: playedTime,
      audioUrl: audioUrl,
      extraId: extraId,
      playlistProgress: _mediaListCoordinator.buildAudioProgressSnapshot(
        currentAid: aid,
        currentCid: cid.value,
        currentProgress: playedTime?.inSeconds,
        currentDuration: VideoMediaListCoordinator.resolveDurationSeconds(
          timeLengthMilliseconds: data.timeLength,
          fallbackDuration: playedTime,
        ),
      ),
    );
  }

  Future<void> onDownload(BuildContext context) async {
    VideoDetailData? videoDetail;
    List<ugc.BaseEpisodeItem>? episodes;
    UgcIntroController? ugcIntroController;
    PgcInfoModel? pgcItem;
    if (isUgc) {
      try {
        ugcIntroController = Get.find<UgcIntroController>(tag: heroTag);
        videoDetail = ugcIntroController.videoDetail.value;
        if (videoDetail.ugcSeason?.sections case final sections?) {
          episodes = <ugc.BaseEpisodeItem>[];
          for (final i in sections) {
            if (i.episodes case final e?) {
              episodes.addAll(e);
            }
          }
        } else {
          episodes = videoDetail.pages;
        }
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('download ugc: $e\n\n$s');
        }
      }
    } else {
      try {
        pgcItem = Get.find<PgcIntroController>(tag: heroTag).pgcItem;
        episodes = pgcItem.episodes;
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('download pgc: $e\n\n$s');
        }
      }
    }
    if (episodes != null && episodes.isNotEmpty) {
      final downloadService = Get.find<DownloadService>();
      await downloadService.waitForInitialization;
      if (!context.mounted) {
        return;
      }
      final Set<int> cidSet = downloadService.downloadList
          .followedBy(downloadService.waitDownloadQueue)
          .map((e) => e.cid)
          .toSet();
      final index = episodes.indexWhere(
        (e) => e.cid == (seasonCid ?? cid.value),
      );

      showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxWidth: min(640, context.mediaQueryShortestSide),
        ),
        builder: (context) {
          final maxChildSize =
              PlatformUtils.isMobile && !context.mediaQuerySize.isPortrait
              ? 1.0
              : 0.7;
          return DraggableScrollableSheet(
            snap: true,
            expand: false,
            minChildSize: 0,
            snapSizes: [maxChildSize],
            maxChildSize: maxChildSize,
            initialChildSize: maxChildSize,
            builder: (context, scrollController) => DownloadPanel(
              index: index,
              videoDetail: videoDetail,
              pgcItem: pgcItem,
              episodes: episodes!,
              scrollController: scrollController,
              videoDetailController: this,
              heroTag: heroTag,
              ugcIntroController: ugcIntroController,
              cidSet: cidSet,
            ),
          );
        },
      );
    }
  }

  void editPlayUrl() {
    String videoUrl = this.videoUrl ?? '';
    String audioUrl = this.audioUrl ?? '';
    Widget textField({
      required String label,
      required String initialValue,
      required ValueChanged<String> onChanged,
    }) => TextFormField(
      minLines: 1,
      maxLines: 3,
      onChanged: onChanged,
      initialValue: initialValue,
      decoration: InputDecoration(
        label: Text(label),
        border: const OutlineInputBorder(),
      ),
    );
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        constraints: Style.dialogFixedConstraints,
        title: const Text('播放地址'),
        content: Column(
          spacing: 20,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            textField(
              label: 'Video Url',
              initialValue: videoUrl,
              onChanged: (value) => videoUrl = value,
            ),
            textField(
              label: 'Audio Url',
              initialValue: audioUrl,
              onChanged: (value) => audioUrl = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              this.videoUrl = videoUrl;
              this.audioUrl = audioUrl;
              playerInit();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  ThemeData get theme => ThemeUtils.theme;

  @pragma('vm:notify-debugger-on-exception')
  Future<void> onCast() async {
    SmartDialog.showLoading();
    final res = await VideoHttp.tvPlayUrl(
      cid: cid.value,
      objectId: epId ?? aid,
      playurlType: epId != null ? 2 : 1,
      qn: currentVideoQa.value?.code,
    );
    SmartDialog.dismiss();
    if (res case Success(:final response)) {
      final first = response.durl?.firstOrNull;
      if (first == null || first.playUrls.isEmpty) {
        SmartDialog.showToast('不支持投屏');
        return;
      }
      final url = VideoUtils.getCdnUrl(first.playUrls);

      String? title;
      try {
        if (isUgc) {
          title = Get.find<UgcIntroController>(
            tag: heroTag,
          ).videoDetail.value.title;
        } else {
          title = Get.find<PgcIntroController>(
            tag: heroTag,
          ).videoDetail.value.title;
        }
      } catch (_) {}
      if (kDebugMode) {
        debugPrint(title);
      }
      Get.toNamed('/dlna', parameters: {'url': url, 'title': ?title});
    } else {
      res.toast();
    }
  }
}
