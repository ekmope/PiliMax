import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:PiliMax/utils/storage/bounded_string_key_lru.dart';
import 'package:PiliMax/utils/storage_key.dart';

final class ReplyCacheStore {
  ReplyCacheStore(
    Box<Uint8List>? box, {
    required Box<dynamic> orderStore,
    this.maxEntries = defaultMaxEntries,
  }) : _box = box,
       _lru = box == null
           ? null
           : BoundedStringKeyLru(
               orderStore: orderStore,
               orderKey: LocalCacheKey.replyWriteOrder,
               maxEntries: maxEntries,
               existingKeys: _seedKeys(orderStore, box),
             );

  static const int defaultMaxEntries = 500;

  final Box<Uint8List>? _box;
  final int maxEntries;
  final BoundedStringKeyLru? _lru;
  Future<void> _operationQueue = Future<void>.value();
  bool _acceptingOperations = true;

  static Iterable<String> _seedKeys(
    Box<dynamic> orderStore,
    Box<Uint8List> box,
  ) {
    final raw = orderStore.get(LocalCacheKey.replyWriteOrder);
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

  bool get isEnabled => _box != null;

  Iterable<Uint8List> get values => _box?.values ?? const [];

  Future<void> enforceLimit() => _enqueue(() async {
    final box = _box;
    final lru = _lru;
    if (box == null || lru == null) return;
    final evict = lru.keysToEvict();
    if (evict.isEmpty) return;
    await box.deleteAll(evict);
    await lru.removeAll(evict);
  });

  Future<void> put(String key, Uint8List value) => _enqueue(() async {
    final box = _box;
    final lru = _lru;
    if (box == null || lru == null) return;

    final evict = lru.keysToEvictAfterTouch([key]);
    await box.put(key, value);
    if (evict.isNotEmpty) {
      await box.deleteAll(evict);
    }
    await lru.touch(key);
  });

  Future<void> putAll(Map<String, Uint8List> values) {
    final snapshot = Map<String, Uint8List>.of(values);
    return _enqueue(() async {
      final box = _box;
      final lru = _lru;
      if (box == null || lru == null || snapshot.isEmpty) return;

      final keys = snapshot.keys.toList(growable: false);
      final evict = lru.keysToEvictAfterTouch(keys);
      final evictSet = evict.toSet();
      final retained = Map<String, Uint8List>.fromEntries(
        snapshot.entries.where((entry) => !evictSet.contains(entry.key)),
      );
      if (retained.isNotEmpty) {
        await box.putAll(retained);
      }
      if (evict.isNotEmpty) {
        await box.deleteAll(evict);
      }
      await lru.touchAll(keys);
    });
  }

  Future<void> delete(String key) => _enqueue(() async {
    await _box?.delete(key);
    await _lru?.remove(key);
  });

  Future<void> clear() => _enqueue(() async {
    await _box?.clear();
    await _lru?.clear();
  });

  Future<void> drain() async {
    while (true) {
      final pending = _operationQueue;
      await pending;
      if (identical(pending, _operationQueue)) return;
    }
  }

  /// Stop accepting new writes, then wait for operations already queued.
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
