import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:PiliMax/http/dynamics.dart';
import 'package:PiliMax/models/dynamics/up.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';

final class DynamicUpReadService {
  static const int _maxConcurrentRequests = 3;
  static const int _maxStoredUpsPerAccount = 5000;
  static const int _storageVersion = 1;

  final Set<String> _pendingReadKeys = <String>{};
  final Map<String, int> _queuedTrailingReadAt = <String, int>{};
  final Map<String, Future<void>> _inFlightReads = <String, Future<void>>{};
  final Queue<Completer<void>> _networkSlotWaiters = Queue<Completer<void>>();
  int _availableNetworkSlots = _maxConcurrentRequests;
  Future<void> _storageQueue = Future<void>.value();

  Set<int> suppressReadUpdates(Iterable<UpItem> items) {
    final accountMid = Accounts.main.mid;
    if (accountMid <= 0) {
      return const <int>{};
    }
    final stored = _readAccountState(accountMid);
    final suppressed = <int>{};
    for (final item in items) {
      if (item.mid <= 0 || item.hasUpdate != true) {
        continue;
      }
      if (stored.containsKey(item.mid) ||
          _pendingReadKeys.contains(_readKey(accountMid, item.mid))) {
        item.hasUpdate = false;
        suppressed.add(item.mid);
      }
    }
    return suppressed;
  }

  Future<Set<int>> resolveSuppressedUpdates({
    required int accountMid,
    required Set<int> mids,
  }) async {
    if (mids.isEmpty || Accounts.main.mid != accountMid) {
      return const <int>{};
    }
    await _storageQueue.catchError((Object _) {});
    final stored = _readAccountState(accountMid);
    final targets = mids.where(stored.containsKey).toSet();
    if (targets.isEmpty) {
      return const <int>{};
    }

    final latest = await _latestMarkers(targets);
    if (Accounts.main.mid != accountMid) {
      return const <int>{};
    }
    final newBaselines = <int, _ReadBaseline>{};
    final markerBackfills = <int, (_ReadBaseline, UpDynamicMarker)>{};
    for (final mid in targets) {
      final result = latest[mid];
      final baseline = stored[mid];
      if (result == null || !result.$1 || baseline == null) {
        continue;
      }
      final marker = result.$2;
      if (marker != null && _isNewerThanBaseline(marker, baseline)) {
        newBaselines[mid] = baseline;
      } else if (marker != null &&
          marker.pubTs > 0 &&
          marker.pubTs <= baseline.readAt &&
          (baseline.idStr.isEmpty || baseline.pubTs <= 0)) {
        markerBackfills[mid] = (baseline, marker);
      }
    }
    final newMids = <int>{};
    if (newBaselines.isNotEmpty || markerBackfills.isNotEmpty) {
      await _mutateAccountState(accountMid, (state) {
        for (final entry in newBaselines.entries) {
          final key = entry.key.toString();
          final current = _ReadBaseline.fromRaw(state[key]);
          if (current != null && current.sameAs(entry.value)) {
            state.remove(key);
            newMids.add(entry.key);
          }
        }
        for (final entry in markerBackfills.entries) {
          final key = entry.key.toString();
          final raw = state[key];
          final current = _ReadBaseline.fromRaw(raw);
          if (raw is Map && current != null && current.sameAs(entry.value.$1)) {
            state[key] = <String, Object?>{
              ...raw,
              'idStr': entry.value.$2.idStr,
              'pubTs': entry.value.$2.pubTs,
            };
          }
        }
      });
    }
    return newMids;
  }

  Future<void> markRead(Iterable<int> mids) {
    final accountMid = Accounts.main.mid;
    if (accountMid <= 0) {
      return Future<void>.value();
    }
    final targets = mids.where((mid) => mid > 0).toSet();
    if (targets.isEmpty) {
      return Future<void>.value();
    }
    final readAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final waits = <Future<void>>{};
    final fresh = <int>{};
    for (final mid in targets) {
      final key = _readKey(accountMid, mid);
      final existing = _inFlightReads[key];
      if (existing == null) {
        fresh.add(mid);
        _pendingReadKeys.add(key);
      } else {
        if (_queuedTrailingReadAt.containsKey(key)) {
          _queuedTrailingReadAt.update(
            key,
            (queuedAt) => math.max(queuedAt, readAt),
          );
          waits.add(existing);
        } else {
          waits.add(
            _queueTrailingRead(
              accountMid: accountMid,
              mid: mid,
              current: existing,
              readAt: readAt,
            ),
          );
        }
      }
    }
    if (fresh.isNotEmpty) {
      late final Future<void> batch;
      batch = _markReadBatch(accountMid, fresh, readAt).whenComplete(() {
        for (final mid in fresh) {
          final key = _readKey(accountMid, mid);
          if (identical(_inFlightReads[key], batch)) {
            _pendingReadKeys.remove(key);
            _inFlightReads.remove(key);
          }
        }
      });
      for (final mid in fresh) {
        _inFlightReads[_readKey(accountMid, mid)] = batch;
      }
      waits.add(batch);
    }
    return Future.wait(waits).then((_) {});
  }

  Future<void> _queueTrailingRead({
    required int accountMid,
    required int mid,
    required Future<void> current,
    required int readAt,
  }) {
    final key = _readKey(accountMid, mid);
    _queuedTrailingReadAt[key] = readAt;
    late final Future<void> trailing;
    trailing = current
        .then((_) async {
          final trailingReadAt = _queuedTrailingReadAt.remove(key) ?? readAt;
          await _markReadBatch(accountMid, {mid}, trailingReadAt);
        })
        .whenComplete(() {
          if (identical(_inFlightReads[key], trailing)) {
            _pendingReadKeys.remove(key);
            _inFlightReads.remove(key);
          }
        });
    _inFlightReads[key] = trailing;
    return trailing;
  }

  Future<void> _markReadBatch(
    int accountMid,
    Set<int> mids,
    int readAt,
  ) async {
    try {
      await _mutateAccountState(accountMid, (state) {
        for (final mid in mids) {
          state[mid.toString()] = <String, Object>{
            'idStr': '',
            'pubTs': 0,
            'readAt': readAt,
          };
        }
      });

      await _captureLatestMarkers(accountMid, mids, readAt);
    } catch (_) {
      // The immediate local UI clear is already complete. A later refresh can
      // retry the local content comparison.
    }
  }

  Future<void> _captureLatestMarkers(
    int accountMid,
    Set<int> mids,
    int readAt,
  ) async {
    final latest = await _latestMarkers(mids);
    await _mutateAccountState(accountMid, (state) {
      for (final mid in mids) {
        final result = latest[mid];
        final marker = result?.$2;
        final key = mid.toString();
        final raw = state[key];
        if (result == null ||
            !result.$1 ||
            marker == null ||
            marker.pubTs <= 0 ||
            marker.pubTs > readAt ||
            raw is! Map ||
            raw['readAt'] != readAt) {
          continue;
        }
        state[key] = <String, Object?>{
          ...raw,
          'idStr': marker.idStr,
          'pubTs': marker.pubTs,
        };
      }
    });
  }

  Future<Map<int, (bool, UpDynamicMarker?)>> _latestMarkers(
    Set<int> mids,
  ) {
    return _mapLimited<(bool, UpDynamicMarker?)>(mids, (mid) async {
      try {
        final response = await _withNetworkSlot(
          () => DynamicsHttp.latestUpDynamic(mid),
        );
        return (response.isSuccess, response.dataOrNull);
      } catch (_) {
        return (false, null);
      }
    });
  }

  Future<T> _withNetworkSlot<T>(Future<T> Function() request) async {
    await _acquireNetworkSlot();
    try {
      return await request();
    } finally {
      _releaseNetworkSlot();
    }
  }

  Future<void> _acquireNetworkSlot() {
    if (_availableNetworkSlots > 0) {
      _availableNetworkSlots--;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _networkSlotWaiters.addLast(waiter);
    return waiter.future;
  }

  void _releaseNetworkSlot() {
    if (_networkSlotWaiters.isNotEmpty) {
      _networkSlotWaiters.removeFirst().complete();
    } else {
      _availableNetworkSlots++;
    }
  }

  Future<Map<int, T>> _mapLimited<T>(
    Set<int> mids,
    Future<T> Function(int mid) action,
  ) async {
    if (mids.isEmpty) {
      return <int, T>{};
    }
    final iterator = mids.iterator;
    final result = <int, T>{};
    Future<void> worker() async {
      while (iterator.moveNext()) {
        final mid = iterator.current;
        result[mid] = await action(mid);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        math.min(_maxConcurrentRequests, mids.length),
        (_) => worker(),
      ),
    );
    return result;
  }

  Map<int, _ReadBaseline> _readAccountState(int accountMid) {
    final root = _stringMap(
      GStorage.localCache.get(LocalCacheKey.dynamicUpReadState),
    );
    final accounts = _stringMap(root['accounts']);
    final account = _stringMap(accounts[accountMid.toString()]);
    final result = <int, _ReadBaseline>{};
    for (final entry in account.entries) {
      final mid = int.tryParse(entry.key);
      final baseline = _ReadBaseline.fromRaw(entry.value);
      if (mid != null && baseline != null) {
        result[mid] = baseline;
      }
    }
    return result;
  }

  Future<void> _mutateAccountState(
    int accountMid,
    void Function(Map<String, dynamic> state) mutate,
  ) {
    final operation = _storageQueue.catchError((Object _) {}).then((_) async {
      final root = _stringMap(
        GStorage.localCache.get(LocalCacheKey.dynamicUpReadState),
      );
      final accounts = _stringMap(root['accounts']);
      final accountKey = accountMid.toString();
      final account = _stringMap(accounts[accountKey]);
      mutate(account);
      _trimAccountState(account);
      if (account.isEmpty) {
        accounts.remove(accountKey);
      } else {
        accounts[accountKey] = account;
      }
      await GStorage.localCache.put(LocalCacheKey.dynamicUpReadState, {
        'version': _storageVersion,
        'accounts': accounts,
      });
    });
    _storageQueue = operation;
    return operation;
  }

  void _trimAccountState(Map<String, dynamic> state) {
    if (state.length <= _maxStoredUpsPerAccount) {
      return;
    }
    final entries = state.entries.toList()
      ..sort((a, b) {
        final aReadAt = _ReadBaseline.fromRaw(a.value)?.readAt ?? 0;
        final bReadAt = _ReadBaseline.fromRaw(b.value)?.readAt ?? 0;
        return aReadAt.compareTo(bReadAt);
      });
    for (final entry in entries.take(state.length - _maxStoredUpsPerAccount)) {
      state.remove(entry.key);
    }
  }

  bool _isNewerThanBaseline(UpDynamicMarker marker, _ReadBaseline baseline) {
    final hasContentBaseline = baseline.pubTs > 0 || baseline.idStr.isNotEmpty;
    if (hasContentBaseline) {
      if (marker.pubTs > 0 && baseline.pubTs > 0) {
        if (marker.pubTs != baseline.pubTs) {
          return marker.pubTs > baseline.pubTs;
        }
      }
      final markerId = BigInt.tryParse(marker.idStr);
      final baselineId = BigInt.tryParse(baseline.idStr);
      if (markerId != null && baselineId != null) {
        return markerId > baselineId;
      }
      return baseline.idStr.isNotEmpty && marker.idStr != baseline.idStr;
    }
    return marker.pubTs > 0 && marker.pubTs > baseline.readAt;
  }

  Map<String, dynamic> _stringMap(Object? raw) {
    if (raw is! Map) {
      return <String, dynamic>{};
    }
    return {
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };
  }

  String _readKey(int accountMid, int upMid) => '$accountMid:$upMid';
}

final class _ReadBaseline {
  const _ReadBaseline({
    required this.idStr,
    required this.pubTs,
    required this.readAt,
  });

  final String idStr;
  final int pubTs;
  final int readAt;

  bool sameAs(_ReadBaseline other) =>
      idStr == other.idStr && pubTs == other.pubTs && readAt == other.readAt;

  static _ReadBaseline? fromRaw(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final pubTs = raw['pubTs'];
    final readAt = raw['readAt'];
    if (pubTs is! int || readAt is! int || readAt <= 0) {
      return null;
    }
    return _ReadBaseline(
      idStr: raw['idStr']?.toString() ?? '',
      pubTs: pubTs,
      readAt: readAt,
    );
  }
}
