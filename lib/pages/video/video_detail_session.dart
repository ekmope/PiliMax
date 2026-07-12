import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/model_hot_video_item.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/utils/storage_pref.dart';

const videoDetailSessionKey = '_videoDetailSession';
const videoDetailPrepareForExitKey = '_videoDetailPrepareForExit';
const videoDetailCancelPreparedExitKey = '_videoDetailCancelPreparedExit';

typedef VideoDetailPrepareForExit = bool Function();

final class VideoDetailSkeletonProfile {
  const VideoDetailSkeletonProfile({
    this.hasSeasonPanel = false,
    this.hasPagesPanel = false,
  });

  final bool hasSeasonPanel;
  final bool hasPagesPanel;
}

/// Owns launch-time data prefetch without creating GetX or player controllers.
final class VideoDetailSession {
  VideoDetailSession._({
    required this.arguments,
    required this.launchContentKey,
    required this.launchOrientationReady,
    required this.skeletonProfileReady,
    required Future<LoadingState<VideoDetailData>>? intro,
    required Future<LoadingState<List<HotVideoItemModel>?>>? related,
  }) : _intro = intro,
       _related = related,
       _currentContentKey = launchContentKey,
       presentationReady = Future.wait<void>([
         if (intro != null) intro.then<void>((_) {}),
         if (related != null) related.then<void>((_) {}),
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
            const VideoDetailSkeletonProfile(),
          )
        : intro.then<VideoDetailSkeletonProfile>(
            _skeletonProfileFromIntro,
            onError: (_, _) => const VideoDetailSkeletonProfile(),
          );

    return VideoDetailSession._(
      arguments: snapshot,
      launchContentKey: launchContentKey,
      launchOrientationReady: launchOrientationReady,
      skeletonProfileReady: skeletonProfileReady,
      intro: intro,
      related: related,
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

  static VideoDetailSkeletonProfile _skeletonProfileFromIntro(
    LoadingState<VideoDetailData> state,
  ) {
    final data = state.dataOrNull;
    return VideoDetailSkeletonProfile(
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
