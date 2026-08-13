import 'dart:collection';

import 'package:PiliMax/grpc/bilibili/app/playurl/v1.pb.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';

final class TrialPlayViewRequestSpec {
  const TrialPlayViewRequestSpec({required this.quality});

  final int quality;
}

abstract final class TrialPlayViewRequestPlan {
  static List<TrialPlayViewRequestSpec> automatic({
    required bool isUgc,
    required bool unlimitedTrialEnabled,
  }) {
    if (!isUgc || !unlimitedTrialEnabled) {
      return const <TrialPlayViewRequestSpec>[];
    }
    return <TrialPlayViewRequestSpec>[
      TrialPlayViewRequestSpec(quality: VideoQuality.super4K.code),
    ];
  }
}

final class TrialPlayViewRequestCacheKey {
  const TrialPlayViewRequestCacheKey({
    required this.accountMid,
    required this.aid,
    required this.cid,
    required this.quality,
  });

  final int accountMid;
  final int aid;
  final int cid;
  final int quality;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrialPlayViewRequestCacheKey &&
          accountMid == other.accountMid &&
          aid == other.aid &&
          cid == other.cid &&
          quality == other.quality;

  @override
  int get hashCode => Object.hash(accountMid, aid, cid, quality);
}

final class _TrialPlayViewRequestCacheEntry {
  _TrialPlayViewRequestCacheEntry({
    required this.createdAt,
    required this.future,
  });

  final DateTime createdAt;
  final Future<LoadingState<PlayViewReply>?> future;
  bool isInFlight = true;
}

/// Coalesces equal page-session requests and briefly retains only complete
/// successful replies. Errors and structurally incomplete replies can retry.
final class TrialPlayViewRequestCache {
  TrialPlayViewRequestCache({
    this.ttl = const Duration(seconds: 60),
    int maxEntries = 16,
    DateTime Function()? now,
  }) : maxEntries = maxEntries > 0
           ? maxEntries
           : throw ArgumentError.value(maxEntries, 'maxEntries'),
       _now = now ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<
    TrialPlayViewRequestCacheKey,
    _TrialPlayViewRequestCacheEntry
  >
  _entries = LinkedHashMap();

  Future<LoadingState<PlayViewReply>?> request({
    required TrialPlayViewRequestCacheKey key,
    required Future<LoadingState<PlayViewReply>?> Function() loader,
  }) {
    final now = _now();
    _entries.removeWhere(
      (_, entry) => now.difference(entry.createdAt) >= ttl,
    );
    final cached = _entries[key];
    if (cached != null) return cached.future;

    if (_entries.length >= maxEntries) _removeOldestCompleted();

    late final Future<LoadingState<PlayViewReply>?> future;
    future = Future<LoadingState<PlayViewReply>?>.sync(loader);
    final entry = _TrialPlayViewRequestCacheEntry(
      createdAt: now,
      future: future,
    );
    _entries[key] = entry;
    future.then(
      (value) {
        if (!identical(_entries[key], entry)) return;
        entry.isInFlight = false;
        final complete = switch (value) {
          Success<PlayViewReply>(:final response) => response.hasVideoInfo(),
          _ => false,
        };
        if (!complete) {
          _entries.remove(key);
        } else {
          _trimCompletedEntries();
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_entries[key], entry)) {
          entry.isInFlight = false;
          _entries.remove(key);
        }
      },
    );
    return future;
  }

  void _removeOldestCompleted() {
    TrialPlayViewRequestCacheKey? oldestCompletedKey;
    for (final entry in _entries.entries) {
      if (!entry.value.isInFlight) {
        oldestCompletedKey = entry.key;
        break;
      }
    }
    if (oldestCompletedKey != null) _entries.remove(oldestCompletedKey);
  }

  void _trimCompletedEntries() {
    while (_entries.length > maxEntries) {
      final before = _entries.length;
      _removeOldestCompleted();
      if (_entries.length == before) return;
    }
  }

  void clear() => _entries.clear();
}
