import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:PiliMax/utils/storage/bounded_string_key_lru.dart';
import 'package:PiliMax/utils/storage/reply_cache_store.dart';
import 'package:PiliMax/utils/storage/watch_progress_store.dart';
import 'package:PiliMax/utils/storage_key.dart';

void main() {
  late Directory hiveDirectory;
  late Box<int> progressBox;
  late Box<Uint8List> replyBox;
  late Box<dynamic> orderBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pilimax_lru_test_');
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    progressBox = await Hive.openBox<int>(
      'progress_${DateTime.now().microsecondsSinceEpoch}',
      keyComparator: _numericStringDescKeyComparator,
    );
    replyBox = await Hive.openBox<Uint8List>(
      'reply_${DateTime.now().microsecondsSinceEpoch}',
      keyComparator: _numericStringDescKeyComparator,
    );
    orderBox = await Hive.openBox<dynamic>(
      'order_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    await progressBox.deleteFromDisk();
    await replyBox.deleteFromDisk();
    await orderBox.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('BoundedStringKeyLru reports oldest keys for eviction', () {
    final lru = BoundedStringKeyLru(
      orderStore: orderBox,
      orderKey: 'order',
      maxEntries: 3,
      existingKeys: const ['a', 'b', 'c'],
    );
    expect(lru.keysToEvict(incoming: 1), ['a']);
  });

  test('legacy descending boxes evict oldest keys on first limit', () async {
    await progressBox.putAll({for (var i = 1; i <= 5; i++) '$i': i});
    await replyBox.putAll({
      for (var i = 1; i <= 5; i++) '$i': Uint8List.fromList([i]),
    });

    final progressStore = WatchProgressStore(
      progressBox,
      orderStore: orderBox,
      maxEntries: 3,
    );
    final replyStore = ReplyCacheStore(
      replyBox,
      orderStore: orderBox,
      maxEntries: 3,
    );

    await Future.wait([
      progressStore.enforceLimit(),
      replyStore.enforceLimit(),
    ]);

    expect(progressBox.keys.toSet(), {'3', '4', '5'});
    expect(replyBox.keys.toSet(), {'3', '4', '5'});
    expect(
      orderBox.get(LocalCacheKey.watchProgressWriteOrder),
      ['3', '4', '5'],
    );
    expect(orderBox.get(LocalCacheKey.replyWriteOrder), ['3', '4', '5']);
  });

  test('WatchProgressStore evicts oldest writes beyond maxEntries', () async {
    final store = WatchProgressStore(
      progressBox,
      orderStore: orderBox,
      maxEntries: 3,
    );

    await store.put('1', 10);
    await store.put('2', 20);
    await store.put('3', 30);
    await store.put('4', 40);

    expect(progressBox.keys.map((key) => key.toString()).toSet(), {
      '2',
      '3',
      '4',
    });
    expect(store.get('1'), isNull);
    expect(store.get('4'), 40);
    expect(
      orderBox.get(LocalCacheKey.watchProgressWriteOrder),
      ['2', '3', '4'],
    );
  });

  test(
    'WatchProgressStore refresh keeps existing key without eviction',
    () async {
      final store = WatchProgressStore(
        progressBox,
        orderStore: orderBox,
        maxEntries: 2,
      );
      await store.put('1', 10);
      await store.put('2', 20);
      await store.put('1', 11);
      expect(progressBox.length, 2);
      expect(store.get('1'), 11);
      expect(
        orderBox.get(LocalCacheKey.watchProgressWriteOrder),
        ['2', '1'],
      );
    },
  );

  test('ReplyCacheStore evicts oldest writes beyond maxEntries', () async {
    final store = ReplyCacheStore(
      replyBox,
      orderStore: orderBox,
      maxEntries: 2,
    );
    await store.put('r1', Uint8List.fromList([1]));
    await store.put('r2', Uint8List.fromList([2]));
    await store.put('r3', Uint8List.fromList([3]));

    expect(replyBox.keys.map((key) => key.toString()).toSet(), {'r2', 'r3'});
    expect(
      orderBox.get(LocalCacheKey.replyWriteOrder),
      ['r2', 'r3'],
    );
  });

  test('ReplyCacheStore caps a single oversized batch', () async {
    final store = ReplyCacheStore(
      replyBox,
      orderStore: orderBox,
      maxEntries: 3,
    );

    await store.putAll({
      for (var i = 1; i <= 6; i++) 'r$i': Uint8List.fromList([i]),
    });

    expect(replyBox.keys.map((key) => key.toString()).toSet(), {
      'r4',
      'r5',
      'r6',
    });
    expect(orderBox.get(LocalCacheKey.replyWriteOrder), ['r4', 'r5', 'r6']);
  });

  test('ReplyCacheStore serializes concurrent writes at the limit', () async {
    final store = ReplyCacheStore(
      replyBox,
      orderStore: orderBox,
      maxEntries: 3,
    );

    await Future.wait([
      for (var i = 1; i <= 6; i++) store.put('r$i', Uint8List.fromList([i])),
    ]);

    expect(replyBox.keys.map((key) => key.toString()).toSet(), {
      'r4',
      'r5',
      'r6',
    });
    expect(orderBox.get(LocalCacheKey.replyWriteOrder), ['r4', 'r5', 'r6']);
  });

  test('drain waits for unawaited queued writes before close', () async {
    final progressStore = WatchProgressStore(
      progressBox,
      orderStore: orderBox,
      maxEntries: 3,
    );
    final replyStore = ReplyCacheStore(
      replyBox,
      orderStore: orderBox,
      maxEntries: 3,
    );
    final writes = <Future<void>>[
      progressStore.put('1', 10),
      progressStore.put('2', 20),
      replyStore.put('r1', Uint8List.fromList([1])),
      replyStore.put('r2', Uint8List.fromList([2])),
    ];

    await Future.wait([progressStore.drain(), replyStore.drain()]);
    await Future.wait(writes);

    expect(progressBox.toMap(), {'1': 10, '2': 20});
    expect(replyBox.keys.toSet(), {'r1', 'r2'});
  });

  test('beginClose drains queued work and rejects later writes', () async {
    final progressStore = WatchProgressStore(
      progressBox,
      orderStore: orderBox,
      maxEntries: 3,
    );
    final replyStore = ReplyCacheStore(
      replyBox,
      orderStore: orderBox,
      maxEntries: 3,
    );

    final pendingProgress = progressStore.put('1', 10);
    final pendingReply = replyStore.put('r1', Uint8List.fromList([1]));
    await Future.wait([
      progressStore.beginClose(),
      replyStore.beginClose(),
    ]);
    await Future.wait([pendingProgress, pendingReply]);
    await progressStore.put('2', 20);
    await replyStore.put('r2', Uint8List.fromList([2]));

    expect(progressBox.toMap(), {'1': 10});
    expect(replyBox.keys.toSet(), {'r1'});
  });
}

int _numericStringDescKeyComparator(dynamic first, dynamic second) {
  final firstString = first.toString();
  final secondString = second.toString();
  final lengthComparison = secondString.length.compareTo(firstString.length);
  return lengthComparison == 0
      ? secondString.compareTo(firstString)
      : lengthComparison;
}
