/// Invalidates preview-image requests independently from the source open queue.
/// A source switch can clear the cache while image decoding is still running;
/// the captured token prevents that late result from repopulating the cache.
final class PreviewRequestEpoch {
  int _generation = 0;

  int get generation => _generation;

  PreviewRequestToken capture(String url) =>
      PreviewRequestToken._(generation: _generation, url: url);

  void invalidate() {
    _generation++;
  }

  bool isCurrent(PreviewRequestToken token) => token.generation == _generation;
}

final class PreviewRequestToken {
  const PreviewRequestToken._({required this.generation, required this.url});

  final int generation;
  final String url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreviewRequestToken &&
          generation == other.generation &&
          url == other.url;

  @override
  int get hashCode => Object.hash(generation, url);
}

/// Applies an asynchronously loaded preview value only while its source epoch
/// is current. The `null` cache value is used as an in-flight sentinel.
final class PreviewLoadCoordinator<T extends Object> {
  const PreviewLoadCoordinator();

  Future<T?> load({
    required PreviewRequestToken token,
    required Map<String, T?> cache,
    required bool Function(PreviewRequestToken token) isRequestCurrent,
    required bool Function() canRetain,
    required Future<T?> Function(String url) loader,
    required void Function(T value) disposeValue,
  }) async {
    final url = token.url;
    final cached = cache[url];
    if (cached != null) return cached;
    if (cache.containsKey(url)) return null;

    cache[url] = null;
    T? value;
    try {
      value = await loader(url);
    } catch (_) {
      value = null;
    }

    if (!isRequestCurrent(token)) {
      if (value != null) disposeValue(value);
      return null;
    }
    if (value == null) {
      if (cache[url] == null) cache.remove(url);
      return null;
    }
    if (!canRetain()) {
      disposeValue(value);
      if (cache[url] == null) cache.remove(url);
      return null;
    }

    final newerCached = cache[url];
    if (newerCached != null) {
      disposeValue(value);
      return newerCached;
    }
    cache[url] = value;
    return value;
  }
}
