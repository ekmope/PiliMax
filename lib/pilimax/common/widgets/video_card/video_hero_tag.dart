abstract final class VideoHeroTag {
  static final Expando<int> _occurrenceIds = Expando<int>(
    'videoHeroOccurrenceId',
  );
  static int _nextOccurrenceId = 0;

  static String forItem({
    required String scope,
    required Object item,
    required Object contentId,
  }) {
    final occurrenceId = _occurrenceIds[item] ??= _nextOccurrenceId++;
    return '$scope-$contentId-$occurrenceId';
  }
}
