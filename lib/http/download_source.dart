import 'package:PiliMax/models/common/video/video_decode_type.dart';
import 'package:PiliMax/models/video/play/url.dart';

class DownloadSourceException implements Exception {
  const DownloadSourceException(this.message);

  final String message;

  @override
  String toString() => 'DownloadSourceException: $message';
}

class DashVideoSelection {
  const DashVideoSelection({
    required this.video,
    required this.format,
  });

  final VideoItem video;
  final FormatItem format;

  int get quality => video.quality.code;
}

abstract final class DownloadSourceSelector {
  static DashVideoSelection selectDashVideo({
    required List<VideoItem>? videos,
    required List<FormatItem>? supportFormats,
    required int preferredQuality,
    required List<VideoDecodeFormatType> preferredCodecs,
  }) {
    if (videos == null || videos.isEmpty) {
      throw const DownloadSourceException('DASH video streams are empty');
    }
    if (supportFormats == null || supportFormats.isEmpty) {
      throw const DownloadSourceException('Supported video formats are empty');
    }

    final playableVideos = videos.where(_isPlayableVideo).toList();
    if (playableVideos.isEmpty) {
      throw const DownloadSourceException(
        'DASH video streams contain no playable source',
      );
    }

    final formatsByQuality = <int, FormatItem>{
      for (final format in supportFormats)
        if (format.quality case final int quality) quality: format,
    };
    final availableQualities = playableVideos
        .map((video) => video.quality.code)
        .where(formatsByQuality.containsKey)
        .toSet();
    if (availableQualities.isEmpty) {
      throw const DownloadSourceException(
        'DASH streams do not match any supported format',
      );
    }

    final targetQuality = closestQuality(
      availableQualities,
      preferredQuality,
    );
    final qualityVideos = playableVideos
        .where((video) => video.quality.code == targetQuality)
        .toList();
    if (qualityVideos.isEmpty) {
      throw DownloadSourceException(
        'No playable DASH stream for quality $targetQuality',
      );
    }

    return DashVideoSelection(
      video: _selectPreferredCodec(qualityVideos, preferredCodecs),
      format: formatsByQuality[targetQuality]!,
    );
  }

  static AudioItem? selectDashAudio({
    required List<AudioItem>? audios,
    required int preferredQuality,
  }) {
    final playableAudios = audios?.where(_isPlayableAudio).toList();
    if (playableAudios == null || playableAudios.isEmpty) {
      return null;
    }
    final targetQuality = closestQuality(
      playableAudios.map((audio) => audio.id!),
      preferredQuality,
    );
    return playableAudios.firstWhere((audio) => audio.id == targetQuality);
  }

  static Durl selectDurl(List<Durl>? durls) {
    if (durls == null || durls.isEmpty) {
      throw const DownloadSourceException(
        'Progressive download URLs are empty',
      );
    }
    for (final durl in durls) {
      if ((durl.order ?? 0) > 0 &&
          (durl.length ?? 0) > 0 &&
          (durl.size ?? 0) > 0 &&
          _hasPlayableUrl(durl.playUrls)) {
        return durl;
      }
    }
    throw const DownloadSourceException(
      'Progressive download URLs contain no playable source',
    );
  }

  static int requirePositiveDuration(int? duration) {
    if (duration == null || duration <= 0) {
      throw const DownloadSourceException(
        'Video duration is missing or invalid',
      );
    }
    return duration;
  }

  static String requireFormat(String? format) {
    if (format == null || format.trim().isEmpty) {
      throw const DownloadSourceException('Video format is missing');
    }
    return format;
  }

  static Iterable<String> playableUrls(Iterable<String> urls) =>
      urls.where((url) => url.trim().isNotEmpty);

  static int closestQuality(
    Iterable<int> qualities,
    int preferredQuality,
  ) {
    final uniqueQualities = qualities.toSet();
    if (uniqueQualities.isEmpty) {
      throw const DownloadSourceException('Available qualities are empty');
    }
    return uniqueQualities.reduce((left, right) {
      final leftDistance = (left - preferredQuality).abs();
      final rightDistance = (right - preferredQuality).abs();
      if (leftDistance != rightDistance) {
        return leftDistance < rightDistance ? left : right;
      }
      return left < right ? left : right;
    });
  }

  static VideoItem _selectPreferredCodec(
    List<VideoItem> videos,
    List<VideoDecodeFormatType> preferredCodecs,
  ) {
    for (final preferredCodec in preferredCodecs) {
      for (final video in videos) {
        if (preferredCodec.codes.any(video.codecs!.startsWith)) {
          return video;
        }
      }
    }
    return videos.first;
  }

  static bool _isPlayableVideo(VideoItem video) =>
      (video.id ?? 0) > 0 &&
      (video.bandWidth ?? 0) > 0 &&
      (video.codecid ?? -1) >= 0 &&
      (video.width ?? 0) > 0 &&
      (video.height ?? 0) > 0 &&
      video.codecs?.isNotEmpty == true &&
      _hasPlayableUrl(video.playUrls);

  static bool _isPlayableAudio(AudioItem audio) =>
      (audio.id ?? 0) > 0 &&
      (audio.bandWidth ?? 0) > 0 &&
      (audio.codecid ?? -1) >= 0 &&
      _hasPlayableUrl(audio.playUrls);

  static bool _hasPlayableUrl(Iterable<String> urls) =>
      playableUrls(urls).isNotEmpty;
}
