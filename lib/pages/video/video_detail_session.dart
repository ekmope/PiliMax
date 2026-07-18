import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/model_hot_video_item.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/storage_pref.dart';

const videoDetailSessionKey = '_videoDetailSession';
const videoDetailPrepareForExitKey = '_videoDetailPrepareForExit';
const videoDetailCancelPreparedExitKey = '_videoDetailCancelPreparedExit';

enum VideoDetailExitMode {
  /// The entry overlay and Hero still own the visible presentation, so the
  /// route animation itself must reverse without another page transform.
  entryReverse,

  /// The route-owned skeleton and cover form one outgoing surface.
  routeComposite,

  /// Argument resolution failed before a real detail page was mounted. The
  /// error page exits independently instead of returning to the launch card.
  errorFallback,

  /// The real detail page is visible and can use the shared/snapshot exit.
  detail,
}

typedef VideoDetailPrepareForExit = VideoDetailExitMode Function();

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
    );
  }

  final Map<dynamic, dynamic> arguments;
  final String launchContentKey;
  final Future<bool?> launchOrientationReady;
  final Future<VideoDetailSkeletonProfile> skeletonProfileReady;
  final Future<void> presentationReady;
  Future<LoadingState<VideoDetailData>>? _intro;
  Future<LoadingState<List<HotVideoItemModel>?>>? _related;
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
    VideoDetailSkeletonProfile base,
  ) {
    final data = state.dataOrNull;
    return base.copyWith(
      hasSeasonPanel: data?.ugcSeason != null,
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
