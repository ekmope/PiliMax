final class SingleFlight<K> {
  final Map<K, Future<void>> _inFlight = <K, Future<void>>{};

  Future<void> run(K key, Future<void> Function() operation) {
    final pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }

    late final Future<void> future;
    future = Future<void>.sync(operation).whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = future;
    return future;
  }
}
