import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/model_hot_video_item.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/utils/storage_pref.dart';

const videoDetailSessionKey = '_videoDetailSession';

/// Owns launch-time data prefetch without creating GetX or player controllers.
final class VideoDetailSession {
  VideoDetailSession._({
    required this.arguments,
    required this.launchContentKey,
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

    return VideoDetailSession._(
      arguments: snapshot,
      launchContentKey: launchContentKey,
      intro: intro,
      related: related,
    );
  }

  final Map<dynamic, dynamic> arguments;
  final String launchContentKey;
  final Future<void> presentationReady;
  Future<LoadingState<VideoDetailData>>? _intro;
  Future<LoadingState<List<HotVideoItemModel>?>>? _related;
  String _currentContentKey;
  bool _disposed = false;

  bool get matchesLaunchContent => _currentContentKey == launchContentKey;

  bool? get launchIsVertical => arguments['videoOrientationKnown'] == true
      ? arguments['isVertical'] as bool?
      : null;

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
