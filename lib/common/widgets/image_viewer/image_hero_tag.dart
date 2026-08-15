/// Stable Hero tag helpers shared by image grids and the image viewer.
///
/// A business-owned scope is preferred. The URL-list fallback keeps existing
/// callers working, while the item index prevents duplicate URLs in one grid
/// from producing duplicate Hero tags.
abstract final class ImageHeroTag {
  static String fallback(Iterable<String> urls) {
    return 'image-grid:${Object.hashAll(urls)}';
  }

  static String item({
    required String scope,
    required String url,
    required int index,
  }) {
    return '$scope:$index:$url';
  }
}
