import 'package:PiliMax/grpc/bilibili/app/playurl/v1.pb.dart' as app;
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/pilimax/services/playback/trial_quality_policy.dart';

final class TrialPlayViewMergeResult {
  const TrialPlayViewMergeResult({
    required this.offeredQualityIds,
    required this.playableQualityIds,
    required this.durationMismatch,
  });

  final Set<int> offeredQualityIds;
  final Set<int> playableQualityIds;
  final bool durationMismatch;
}

/// Adds only URL-backed App preview video streams to a Web play-url model.
/// The Web audio list is intentionally never read or modified here.
abstract final class TrialPlayViewMerger {
  static const durationMismatchTolerance = Duration(seconds: 5);

  static const _codecPrefixes = <int, String>{
    7: 'avc1',
    12: 'hev1',
    13: 'av01',
    20: 'dvh1',
  };

  static final _knownQualities = {
    for (final quality in VideoQuality.values) quality.code: quality,
  };

  static TrialPlayViewMergeResult merge({
    required PlayUrlModel target,
    required app.PlayViewReply reply,
    required bool unlimitedTrialEnabled,
    Set<int>? allowedQualityIds,
  }) {
    final dash = target.dash;
    if (!reply.hasVideoInfo() || dash == null) {
      return _emptyResult();
    }
    if (_hasClearDurationMismatch(target, reply.videoInfo)) {
      return _emptyResult(durationMismatch: true);
    }

    final offeredQualityIds = <int>{};
    final playableQualityIds = <int>{};
    final codecsByQuality = <int, Set<String>>{};
    final streamInfoByQuality = <int, app.StreamInfo>{};

    bool? canWatch;
    int? times;
    if (reply.hasAb() && reply.ab.hasGlance()) {
      final glance = reply.ab.glance;
      canWatch = glance.hasCanWatch() ? glance.canWatch : null;
      times = glance.hasTimes() ? glance.times.toInt() : null;
    }

    final videos = dash.video ??= <VideoItem>[];
    final ordinaryQualityIds = videos
        .where(
          (item) =>
              !item.isPreview &&
              item.playUrls.any((url) => url.trim().isNotEmpty),
        )
        .map((item) => item.quality.code)
        .toSet();
    final seenPreviewStreams = <String>{
      for (final item in videos.where((item) => item.isPreview))
        _videoKey(item),
    };

    for (final stream in reply.videoInfo.streamList) {
      if (!stream.hasStreamInfo()) continue;
      final info = stream.streamInfo;
      final qualityCode = info.quality;
      if (allowedQualityIds != null &&
          !allowedQualityIds.contains(qualityCode)) {
        continue;
      }
      final quality = _knownQualities[qualityCode];
      if (quality == null || ordinaryQualityIds.contains(qualityCode)) {
        continue;
      }

      final hasPreview = info.hasHasPreview() && info.hasPreview;
      if (!hasPreview) continue;

      offeredQualityIds.add(qualityCode);

      final hasPlaybackError =
          info.hasErrCode() && info.errCode != app.PlayErr.NoErr;
      final isDrm = info.hasSupportDrm() && info.supportDrm;

      final dashVideos = switch (stream.whichContent()) {
        app.Stream_Content.dashVideo => <app.DashVideo>[stream.dashVideo],
        app.Stream_Content.multiDashVideo => stream.multiDashVideo.dashVideos,
        _ => const <app.DashVideo>[],
      };
      final actualCodecs = <String>{};

      for (final source in dashVideos) {
        final codec = _codecPrefixes[source.codecid];
        final baseUrl = source.baseUrl.trim();
        final backupUrls = source.backupUrl
            .map((url) => url.trim())
            .where((url) => url.isNotEmpty)
            .toList(growable: false);
        final hasPlayableStream = baseUrl.isNotEmpty || backupUrls.isNotEmpty;
        final sourceIsDrm =
            isDrm ||
            source.widevinePssh.isNotEmpty ||
            source.bilidrmUri.isNotEmpty;
        final canUse =
            codec != null &&
            TrialQualityPolicy.canUseOfficialPreview(
              hasPreview: hasPreview,
              hasPlayableStream: hasPlayableStream,
              hasPlaybackError: hasPlaybackError,
              isDrm: sourceIsDrm,
              unlimitedTrialEnabled: unlimitedTrialEnabled,
              canWatch: canWatch,
              times: times,
            );
        if (!canUse) continue;

        final item = VideoItem(
          id: qualityCode,
          baseUrl: baseUrl.isEmpty ? null : baseUrl,
          backupUrl: backupUrls.isEmpty ? null : backupUrls,
          bandWidth: source.bandwidth,
          mimeType: 'video/mp4',
          codecs: codec,
          width: source.width,
          height: source.height,
          frameRate: source.frameRate,
          codecid: source.codecid,
          quality: quality,
          isPreview: true,
        );
        final key = _videoKey(item);
        if (seenPreviewStreams.add(key)) videos.add(item);
        actualCodecs.add(codec);
        playableQualityIds.add(qualityCode);
      }

      if (actualCodecs.isNotEmpty) {
        (codecsByQuality[qualityCode] ??= <String>{}).addAll(actualCodecs);
        streamInfoByQuality.putIfAbsent(qualityCode, () => info);
      }
    }

    for (final entry in codecsByQuality.entries) {
      _mergeFormat(
        target: target,
        info: streamInfoByQuality[entry.key]!,
        quality: _knownQualities[entry.key]!,
        codecs: entry.value,
      );
    }

    videos.sort((a, b) => b.quality.code.compareTo(a.quality.code));
    target.supportFormats?.sort(
      (a, b) => (b.quality ?? -1).compareTo(a.quality ?? -1),
    );
    final acceptQuality = target.acceptQuality;
    if (acceptQuality != null) {
      for (final quality in playableQualityIds) {
        if (!acceptQuality.contains(quality)) acceptQuality.add(quality);
      }
      acceptQuality.sort((a, b) => b.compareTo(a));
    }

    return TrialPlayViewMergeResult(
      offeredQualityIds: offeredQualityIds,
      playableQualityIds: playableQualityIds,
      durationMismatch: false,
    );
  }

  static bool _hasClearDurationMismatch(
    PlayUrlModel target,
    app.VideoInfo videoInfo,
  ) {
    final webDuration = target.timeLength;
    if (webDuration == null || webDuration <= 0 || !videoInfo.hasTimelength()) {
      return false;
    }
    final appDuration = videoInfo.timelength.toInt();
    if (appDuration <= 0) return false;
    return (appDuration - webDuration).abs() >
        durationMismatchTolerance.inMilliseconds;
  }

  static TrialPlayViewMergeResult _emptyResult({
    bool durationMismatch = false,
  }) => TrialPlayViewMergeResult(
    offeredQualityIds: <int>{},
    playableQualityIds: <int>{},
    durationMismatch: durationMismatch,
  );

  static void _mergeFormat({
    required PlayUrlModel target,
    required app.StreamInfo info,
    required VideoQuality quality,
    required Set<String> codecs,
  }) {
    final formats = target.supportFormats ??= <FormatItem>[];
    FormatItem? format;
    for (final item in formats) {
      if (item.quality == quality.code) {
        format = item;
        break;
      }
    }
    if (format == null) {
      formats.add(
        FormatItem(
          quality: quality.code,
          format: info.format.isEmpty ? quality.shortDesc : info.format,
          newDesc: info.newDescription.isNotEmpty
              ? info.newDescription
              : info.description.isNotEmpty
              ? info.description
              : quality.desc,
          displayDesc: info.displayDesc.isEmpty
              ? quality.shortDesc
              : info.displayDesc,
          codecs: codecs.toList(growable: false),
        ),
      );
    } else {
      format
        ..codecs = codecs.toList(growable: false)
        ..format ??= info.format.isEmpty ? quality.shortDesc : info.format
        ..newDesc ??= info.newDescription.isNotEmpty
            ? info.newDescription
            : info.description.isNotEmpty
            ? info.description
            : quality.desc
        ..displayDesc ??= info.displayDesc.isEmpty
            ? quality.shortDesc
            : info.displayDesc;
    }
  }

  static String _videoKey(VideoItem item) =>
      '${item.quality.code}|${item.codecid}|${item.playUrls.join('|')}';
}
