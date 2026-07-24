import 'package:hive_ce/hive.dart';

/// Approximate write-order LRU for string-keyed boxes.
///
/// [orderStore] persists the write order under [orderKey]. When [maxEntries]
/// is exceeded after a write, the oldest written keys are deleted from [box].
final class BoundedStringKeyLru {
  BoundedStringKeyLru({
    required Box<dynamic> orderStore,
    required this.orderKey,
    required this.maxEntries,
    required Iterable<String> existingKeys,
  }) : assert(maxEntries > 0),
       _orderStore = orderStore {
    final raw = orderStore.get(orderKey);
    final persisted = raw is List
        ? raw.map((item) => item.toString()).toList()
        : <String>[];
    final existing = existingKeys.toSet();
    final next = <String>[];
    final seen = <String>{};
    for (final key in persisted) {
      if (existing.contains(key) && seen.add(key)) {
        next.add(key);
      }
    }
    for (final key in existing) {
      if (seen.add(key)) {
        next.add(key);
      }
    }
    _order
      ..clear()
      ..addAll(next);
  }

  final Box<dynamic> _orderStore;
  final String orderKey;
  final int maxEntries;
  final List<String> _order = <String>[];

  List<String> get order => List<String>.unmodifiable(_order);

  Future<void> touch(String key) async {
    await touchAll([key]);
  }

  Future<void> touchAll(Iterable<String> keys) async {
    for (final key in keys) {
      _order
        ..remove(key)
        ..add(key);
    }
    final overflow = _order.length - maxEntries;
    if (overflow > 0) {
      _order.removeRange(0, overflow);
    }
    await _persist();
  }

  Future<void> remove(String key) async {
    if (_order.remove(key)) {
      await _persist();
    }
  }

  Future<void> removeAll(Iterable<String> keys) async {
    var changed = false;
    for (final key in keys) {
      if (_order.remove(key)) {
        changed = true;
      }
    }
    if (changed) {
      await _persist();
    }
  }

  Future<void> clear() async {
    if (_order.isEmpty) return;
    _order.clear();
    await _persist();
  }

  /// Returns keys that must be deleted to keep [maxEntries].
  List<String> keysToEvict({int incoming = 0}) {
    final overflow = _order.length + incoming - maxEntries;
    if (overflow <= 0) return const [];
    return _order.take(overflow).toList(growable: false);
  }

  /// Computes the eviction set after moving [keys] to the newest positions.
  /// This also handles a single batch that is larger than [maxEntries].
  List<String> keysToEvictAfterTouch(Iterable<String> keys) {
    final projected = List<String>.of(_order);
    for (final key in keys) {
      projected
        ..remove(key)
        ..add(key);
    }
    final overflow = projected.length - maxEntries;
    if (overflow <= 0) return const [];
    return projected.take(overflow).toList(growable: false);
  }

  Future<void> _persist() => _orderStore.put(orderKey, List<String>.of(_order));
}
