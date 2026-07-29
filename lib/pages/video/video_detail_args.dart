import 'package:PiliMax/models/common/video/video_type.dart';

abstract final class VideoDetailArgs {
  static Map normalize(dynamic rawArgs) {
    if (rawArgs is Map) {
      final heroTag = rawArgs['heroTag'];
      final videoType = rawArgs['videoType'];
      final hasHeroTag = heroTag is String && heroTag.isNotEmpty;
      final normalizedVideoType = _normalizeVideoType(videoType);
      if (hasHeroTag && identical(videoType, normalizedVideoType)) {
        return rawArgs;
      }

      final fallbackHeroTag = _fallbackHeroTag(rawArgs);
      try {
        if (!hasHeroTag) {
          rawArgs['heroTag'] = fallbackHeroTag;
        }
        rawArgs['videoType'] = normalizedVideoType;
        return rawArgs;
      } catch (_) {
        return {
          ...rawArgs,
          if (!hasHeroTag) 'heroTag': fallbackHeroTag,
          'videoType': normalizedVideoType,
        };
      }
    }

    return {
      'heroTag': _fallbackHeroTag(rawArgs),
      'videoType': VideoType.ugc,
    };
  }

  static VideoType _normalizeVideoType(dynamic value) => switch (value) {
    VideoType() => value,
    String() => VideoType.values.firstWhere(
      (videoType) => videoType.name == value,
      orElse: () => VideoType.ugc,
    ),
    _ => VideoType.ugc,
  };

  static String _fallbackHeroTag(dynamic rawArgs) {
    final cid = rawArgs is Map ? rawArgs['cid'] : null;
    return 'video-detail-${cid ?? 'unknown'}-${identityHashCode(rawArgs)}';
  }
}
