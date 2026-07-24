import 'package:hive_ce/hive.dart';
import 'package:PiliMax/utils/storage/bounded_string_key_lru.dart';
import 'package:PiliMax/utils/storage_key.dart';

final class WatchProgressStore {
  WatchProgressStore(
    this._box, {
    required Box<dynamic> orderStore,
    this.maxEntries = defaultMaxEntries,
  }) : _lru = BoundedStringKeyLru(
         orderStore: orderStore,
         orderKey: LocalCacheKey.watchProgressWriteOrder,
         maxEntries: maxEntries,
         // Lazy MMKV boxes expose keys without decoding their values.
         existingKeys: _seedKeys(orderStore, _box),
       );

  static const int defaultMaxEntries = 2000;

  final Box<int> _box;
  final int maxEntries;
  final BoundedStringKeyLru _lru;
  Future<void> _operationQueue = Future<void>.value();
  bool _acceptingOperations = true;

  static Iterable<String> _seedKeys(Box<dynamic> orderStore, Box<int> box) {
    final raw = orderStore.get(LocalCacheKey.watchProgressWriteOrder);
    // The production box comparator is newest-first; the LRU sequence is
    // oldest-first so its head is the next eviction candidate.
    final oldestFirstKeys = box.keys
        .map((key) => key.toString())
        .toList(growable: false)
        .reversed;
    if (raw is List && raw.isNotEmpty) {
      return <String>{
        ...raw.map((item) => item.toString()).where(box.containsKey),
        ...oldestFirstKeys,
      };
    }
    return oldestFirstKeys;
  }

  int? get(String key) => _box.get(key);

  Future<void> enforceLimit() => _enqueue(() async {
    final evict = _lru.keysToEvict();
    if (evict.isEmpty) return;
    await _box.deleteAll(evict);
    await _lru.removeAll(evict);
  });

  Future<void> put(String key, int progress) => _enqueue(() async {
    final evict = _lru.keysToEvictAfterTouch([key]);
    await _box.put(key, progress);
    if (evict.isNotEmpty) {
      await _box.deleteAll(evict);
    }
    await _lru.touch(key);
  });

  Future<void> delete(String key) => _enqueue(() async {
    await _box.delete(key);
    await _lru.remove(key);
  });

  Future<void> deleteAll(Iterable<String> keys) {
    final list = keys.toList(growable: false);
    return _enqueue(() async {
      await _box.deleteAll(list);
      await _lru.removeAll(list);
    });
  }

  Future<void> clear() => _enqueue(() async {
    await _box.clear();
    await _lru.clear();
  });

  Future<void> drain() async {
    while (true) {
      final pending = _operationQueue;
      await pending;
      if (identical(pending, _operationQueue)) return;
    }
  }

  /// Stop accepting new writes, then wait for operations already queued.
  ///
  /// Callers use this before closing the underlying Hive/MMKV box so an
  /// unawaited producer cannot enqueue work against a closed box.
  Future<void> beginClose() {
    _acceptingOperations = false;
    return drain();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (!_acceptingOperations) return Future<void>.value();
    final next = _operationQueue.then((_) => operation());
    _operationQueue = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}
