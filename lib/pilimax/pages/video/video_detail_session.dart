import 'dart:io' show Platform;

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/model_hot_video_item.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/pilimax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/pilimax/services/playback/trial_quality_policy.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/utils/storage_pref.dart';

const videoDetailSessionKey = '_videoDetailSession';
const videoDetailPrepareForExitKey = '_videoDetailPrepareForExit';
const videoDetailCancelPreparedExitKey = '_videoDetailCancelPreparedExit';
const videoDetailPipExitIntentKey = '_videoDetailPipExitIntent';

enum VideoDetailExitMode {
  /// The entry overlay and Hero still own the visible presentation, so the
  /// route animation itself must reverse without another page transform.
  entryReverse,

  /// The route-owned skeleton and cover form one outgoing surface.
  routeComposite,

  /// Argument resolution failed before a real detail page was mounted. The
  /// error page exits independently instead of returning to the launch card.
  errorFallback,

  /// The real detail page is visible and can use the shared live-tree exit.
  detail,
}

typedef VideoDetailPrepareForExit = VideoDetailExitMode Function();
typedef VideoDetailPipExitIntent = bool Function();
typedef VideoDetailPlayUrlLoader =
    Future<LoadingState<PlayUrlModel>> Function();

final class VideoDetailPlayUrlRequest {
  const VideoDetailPlayUrlRequest({
    required this.bvid,
    required this.cid,
    required this.epId,
    required this.seasonId,
    required this.qn,
    required this.tryLook,
    required this.videoType,
    required this.language,
    required this.voiceBalance,
    required this.videoAccountIdentity,
    required this.videoAccountMid,
  });

  factory VideoDetailPlayUrlRequest.forCurrentVideoAccount({
    required String bvid,
    required int cid,
    required int? epId,
    required int? seasonId,
    int qn = 80,
    required bool tryLook,
    required VideoType videoType,
    required String? language,
    required bool voiceBalance,
  }) {
    final account = Accounts.get(AccountType.video);
    return VideoDetailPlayUrlRequest(
      bvid: bvid,
      cid: cid,
      epId: epId,
      seasonId: seasonId,
      qn: qn,
      tryLook: tryLook,
      videoType: videoType,
      language: language,
      voiceBalance: voiceBalance,
      videoAccountIdentity: identityHashCode(account),
      videoAccountMid: account.mid,
    );
  }

  final String bvid;
  final int cid;
  final int? epId;
  final int? seasonId;
  final int qn;
  final bool tryLook;
  final VideoType videoType;
  final String? language;
  final bool voiceBalance;
  final int videoAccountIdentity;
  final int videoAccountMid;

  static VideoType actualVideoType({
    required VideoType requestedVideoType,
    required bool isVideoAccountLoggedIn,
    required bool usePgcApi,
  }) {
    if (requestedVideoType == VideoType.pgc && !isVideoAccountLoggedIn) {
      return VideoType.ugc;
    }
    if (requestedVideoType != VideoType.pgc && usePgcApi) {
      return VideoType.pgc;
    }
    return requestedVideoType;
  }

  static VideoDetailPlayUrlRequest? fromLaunchArguments(
    Map<dynamic, dynamic> arguments,
  ) {
    if (arguments['fromPip'] == true ||
        arguments['sourceType'] == SourceType.file) {
      return null;
    }
    final bvid = arguments['bvid'];
    final cid = arguments['cid'];
    if (bvid is! String || bvid.isEmpty || cid is! int || cid <= 0) {
      return null;
    }
    final account = Accounts.get(AccountType.video);
    final requestedVideoType = arguments['videoType'] is VideoType
        ? arguments['videoType'] as VideoType
        : VideoType.ugc;
    return VideoDetailPlayUrlRequest.forCurrentVideoAccount(
      bvid: bvid,
      cid: cid,
      epId: arguments['epId'] as int?,
      seasonId: arguments['seasonId'] as int?,
      tryLook: TrialQualityPolicy.shouldRequestWebTryLook(
        isLoggedIn: account.isLogin,
        allowAnonymous1080: Pref.p1080,
      ),
      videoType: actualVideoType(
        requestedVideoType: requestedVideoType,
        isVideoAccountLoggedIn: account.isLogin,
        usePgcApi: arguments['pgcApi'] == true,
      ),
      language: null,
      voiceBalance: Platform.isAndroid && Pref.audioNormalization != '0',
    );
  }

  Future<LoadingState<PlayUrlModel>> load() => VideoHttp.videoUrl(
    bvid: bvid,
    cid: cid,
    qn: qn,
    epid: epId,
    seasonId: seasonId,
    tryLook: tryLook,
    videoType: videoType,
    language: language,
    voiceBalance: voiceBalance,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoDetailPlayUrlRequest &&
          bvid == other.bvid &&
          cid == other.cid &&
          epId == other.epId &&
          seasonId == other.seasonId &&
          qn == other.qn &&
          tryLook == other.tryLook &&
          videoType == other.videoType &&
          language == other.language &&
          voiceBalance == other.voiceBalance &&
          videoAccountIdentity == other.videoAccountIdentity &&
          videoAccountMid == other.videoAccountMid;

  @override
  int get hashCode => Object.hash(
    bvid,
    cid,
    epId,
    seasonId,
    qn,
    tryLook,
    videoType,
    language,
    voiceBalance,
    videoAccountIdentity,
    videoAccountMid,
  );
}

final class VideoDetailPlayUrlPrefetch {
  VideoDetailPlayUrlPrefetch.start(
    this.request, {
    VideoDetailPlayUrlLoader? loader,
  }) : _result = _loadSafely(loader ?? request.load);

  final VideoDetailPlayUrlRequest request;
  Future<LoadingState<PlayUrlModel>>? _result;
  bool _disposed = false;

  static Future<LoadingState<PlayUrlModel>> _loadSafely(
    VideoDetailPlayUrlLoader loader,
  ) async {
    try {
      return await loader();
    } catch (error, stackTrace) {
      return Error('$error\n\n$stackTrace');
    }
  }

  Future<LoadingState<PlayUrlModel>>? takeIfMatches(
    VideoDetailPlayUrlRequest candidate,
  ) {
    final result = _result;
    _result = null;
    if (_disposed || request != candidate) {
      return null;
    }
    return result;
  }

  void dispose() {
    _disposed = true;
    _result = null;
  }
}

final class VideoDetailSkeletonProfile {
  const VideoDetailSkeletonProfile({
    this.hasSeasonPanel = false,
    this.hasPagesPanel = false,
    this.tabCount = VideoDetailLayoutMetrics.defaultTabCount,
    this.actionCount = VideoDetailLayoutMetrics.ugcActionCount,
    this.hasEpisodePanel = false,
  }) : assert(tabCount > 0),
       assert(actionCount >= 0);

  final bool hasSeasonPanel;
  final bool hasPagesPanel;
  final int tabCount;
  final int actionCount;
  final bool hasEpisodePanel;

  VideoDetailSkeletonProfile copyWith({
    bool? hasSeasonPanel,
    bool? hasPagesPanel,
    int? tabCount,
    int? actionCount,
    bool? hasEpisodePanel,
  }) => VideoDetailSkeletonProfile(
    hasSeasonPanel: hasSeasonPanel ?? this.hasSeasonPanel,
    hasPagesPanel: hasPagesPanel ?? this.hasPagesPanel,
    tabCount: tabCount ?? this.tabCount,
    actionCount: actionCount ?? this.actionCount,
    hasEpisodePanel: hasEpisodePanel ?? this.hasEpisodePanel,
  );
}

/// Owns launch-time data prefetch without creating GetX or player controllers.
final class VideoDetailSession {
  VideoDetailSession._(
    this._related, {
    required this.arguments,
    required this.launchContentKey,
    required this.launchOrientationReady,
    required this.skeletonProfileReady,
    required Future<LoadingState<VideoDetailData>>? intro,
    required this._playUrlPrefetch,
  }) : _intro = intro,
       _currentContentKey = launchContentKey,
       presentationReady = Future.wait<void>([
         if (intro != null) intro.then<void>((_) {}),
       ]);

  factory VideoDetailSession.start(Map<dynamic, dynamic> arguments) {
    final snapshot = Map<dynamic, dynamic>.from(arguments);
    final launchContentKey = contentKeyFor(snapshot);
    final isPipRestore = snapshot['fromPip'] == true;
    final isFileSource = snapshot['sourceType'] == SourceType.file;
    final videoType = snapshot['videoType'];
    final bvid = snapshot['bvid'];
    final launchIsVertical = snapshot['videoOrientationKnown'] == true
        ? snapshot['isVertical'] as bool?
        : null;
    final launchSkeletonProfile = skeletonProfileFor(snapshot);

    final playUrlRequest = VideoDetailPlayUrlRequest.fromLaunchArguments(
      snapshot,
    );
    final playUrlPrefetch = playUrlRequest == null
        ? null
        : VideoDetailPlayUrlPrefetch.start(playUrlRequest);

    Future<LoadingState<VideoDetailData>>? intro;
    Future<LoadingState<List<HotVideoItemModel>?>>? related;
    if (!isPipRestore &&
        !isFileSource &&
        videoType == VideoType.ugc &&
        bvid is String &&
        bvid.isNotEmpty) {
      intro = VideoHttp.videoIntro(bvid: bvid);
      if (Pref.showRelatedVideo) {
        related = VideoHttp.relatedVideoList(bvid: bvid);
      }
    }

    final launchOrientationReady = launchIsVertical != null || intro == null
        ? Future<bool?>.value(launchIsVertical)
        : intro.then<bool?>(
            (state) => _orientationFromIntro(state) ?? launchIsVertical,
            onError: (_, _) => launchIsVertical,
          );
    final skeletonProfileReady = intro == null
        ? Future<VideoDetailSkeletonProfile>.value(
            launchSkeletonProfile,
          )
        : intro.then<VideoDetailSkeletonProfile>(
            (state) => _skeletonProfileFromIntro(
              state,
              launchSkeletonProfile,
              currentCid: snapshot['cid'] as int?,
            ),
            onError: (_, _) => launchSkeletonProfile,
          );

    return VideoDetailSession._(
      related,
      arguments: snapshot,
      launchContentKey: launchContentKey,
      launchOrientationReady: launchOrientationReady,
      skeletonProfileReady: skeletonProfileReady,
      intro: intro,
      playUrlPrefetch: playUrlPrefetch,
    );
  }

  final Map<dynamic, dynamic> arguments;
  final String launchContentKey;
  final Future<bool?> launchOrientationReady;
  final Future<VideoDetailSkeletonProfile> skeletonProfileReady;
  final Future<void> presentationReady;
  Future<LoadingState<VideoDetailData>>? _intro;
  Future<LoadingState<List<HotVideoItemModel>?>>? _related;
  VideoDetailPlayUrlPrefetch? _playUrlPrefetch;
  String _currentContentKey;
  bool _disposed = false;

  bool get matchesLaunchContent => _currentContentKey == launchContentKey;

  bool? get launchIsVertical => arguments['videoOrientationKnown'] == true
      ? arguments['isVertical'] as bool?
      : null;

  static bool? _orientationFromIntro(
    LoadingState<VideoDetailData> state,
  ) {
    final dimension = state.dataOrNull?.dimension;
    final width = dimension?.width;
    final height = dimension?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return dimension!.isVertical;
  }

  static VideoDetailSkeletonProfile skeletonProfileFor(
    Map<dynamic, dynamic> arguments,
  ) {
    final variant = arguments['sourceType'] == SourceType.file
        ? VideoDetailSkeletonVariant.local
        : switch (arguments['videoType']) {
            VideoType.pgc => VideoDetailSkeletonVariant.pgc,
            VideoType.pugv => VideoDetailSkeletonVariant.pugv,
            _ => VideoDetailSkeletonVariant.ugc,
          };
    final showReply = switch (variant) {
      VideoDetailSkeletonVariant.ugc => Pref.showVideoReply,
      VideoDetailSkeletonVariant.pgc ||
      VideoDetailSkeletonVariant.pugv => Pref.showBangumiReply,
      VideoDetailSkeletonVariant.local => false,
    };
    final pgcItem = arguments['pgcItem'];
    final hasEpisodePanel =
        pgcItem is PgcInfoModel && pgcItem.episodes?.isNotEmpty == true;
    return VideoDetailSkeletonProfile(
      tabCount: VideoDetailLayoutMetrics.portraitTabCount(
        variant: variant,
        showReply: showReply,
      ),
      actionCount: VideoDetailLayoutMetrics.actionCountFor(
        variant,
        includeAiAction: Pref.enableAiChat,
      ),
      hasEpisodePanel: hasEpisodePanel,
    );
  }

  static VideoDetailSkeletonProfile _skeletonProfileFromIntro(
    LoadingState<VideoDetailData> state,
    VideoDetailSkeletonProfile base, {
    required int? currentCid,
  }) {
    final data = state.dataOrNull;
    return base.copyWith(
      hasSeasonPanel: hasRenderableUgcSeasonPanel(data, currentCid),
      hasPagesPanel: (data?.pages?.length ?? 0) > 1,
    );
  }

  Future<LoadingState<VideoDetailData>>? takeInitialIntro() {
    final value = _intro;
    _intro = null;
    return value;
  }

  Future<LoadingState<List<HotVideoItemModel>?>>? takeInitialRelated() {
    final value = _related;
    _related = null;
    return value;
  }

  Future<LoadingState<PlayUrlModel>>? takeInitialPlayUrl(
    VideoDetailPlayUrlRequest request,
  ) {
    final prefetch = _playUrlPrefetch;
    _playUrlPrefetch = null;
    if (_disposed || !matchesLaunchContent) {
      prefetch?.dispose();
      return null;
    }
    return prefetch?.takeIfMatches(request);
  }

  void updateCurrentContent({
    required VideoType videoType,
    required int? aid,
    required String? bvid,
    required int? cid,
    required int? seasonId,
    required int? epId,
  }) {
    if (_disposed) {
      return;
    }
    _currentContentKey = contentKey(
      videoType: videoType,
      aid: aid,
      bvid: bvid,
      cid: cid,
      seasonId: seasonId,
      epId: epId,
    );
  }

  void dispose() {
    _disposed = true;
    _intro = null;
    _related = null;
    _playUrlPrefetch?.dispose();
    _playUrlPrefetch = null;
  }

  static String contentKeyFor(Map<dynamic, dynamic> arguments) => contentKey(
    videoType: arguments['videoType'] is VideoType
        ? arguments['videoType'] as VideoType
        : VideoType.ugc,
    aid: arguments['aid'] as int?,
    bvid: arguments['bvid'] as String?,
    cid: arguments['cid'] as int?,
    seasonId: arguments['seasonId'] as int?,
    epId: arguments['epId'] as int?,
  );

  static String contentKey({
    required VideoType videoType,
    required int? aid,
    required String? bvid,
    required int? cid,
    required int? seasonId,
    required int? epId,
  }) => switch (videoType) {
    VideoType.ugc => 'ugc:${bvid ?? aid ?? 'unknown'}:${cid ?? 'unknown'}',
    VideoType.pgc =>
      'pgc:${epId ?? seasonId ?? bvid ?? aid ?? 'unknown'}:${cid ?? 'unknown'}',
    VideoType.pugv =>
      'pugv:${epId ?? seasonId ?? bvid ?? aid ?? 'unknown'}:${cid ?? 'unknown'}',
  };
}
