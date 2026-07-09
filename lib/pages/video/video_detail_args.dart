abstract final class VideoDetailArgs {
  static Map normalize(dynamic rawArgs) {
    if (rawArgs is Map) {
      final heroTag = rawArgs['heroTag'];
      if (heroTag is String && heroTag.isNotEmpty) {
        return rawArgs;
      }

      final fallbackHeroTag = _fallbackHeroTag(rawArgs);
      try {
        rawArgs['heroTag'] = fallbackHeroTag;
        return rawArgs;
      } catch (_) {
        return {
          ...rawArgs,
          'heroTag': fallbackHeroTag,
        };
      }
    }

    return {
      'heroTag': _fallbackHeroTag(rawArgs),
    };
  }

  static String _fallbackHeroTag(dynamic rawArgs) {
    final cid = rawArgs is Map ? rawArgs['cid'] : null;
    return 'video-detail-${cid ?? 'unknown'}-${identityHashCode(rawArgs)}';
  }
}
