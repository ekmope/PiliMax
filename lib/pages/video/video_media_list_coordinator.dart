import 'dart:math';

import 'package:PiliMax/models/common/list_order.dart';
import 'package:PiliMax/models_new/media_list/media_list.dart';
import 'package:get/get.dart';

enum VideoMediaListLoadType { replace, previous, next }

final class VideoMediaListRequest {
  const VideoMediaListRequest._({
    required this.id,
    required this.generation,
    required this.order,
    required this.type,
    required this.page,
    required this.playbackIdentity,
  });

  final int id;
  final int generation;
  final ListOrder order;
  final VideoMediaListLoadType type;
  final int? page;
  final Object playbackIdentity;

  bool get isReverse => type == VideoMediaListLoadType.replace;
  bool get isLoadPrevious => type == VideoMediaListLoadType.previous;
}

final class VideoMediaListApplyResult {
  const VideoMediaListApplyResult({
    required this.accepted,
    this.nextEpisode,
    this.hasMoreShufflePages = false,
  });

  final bool accepted;
  final MediaListItemModel? nextEpisode;
  final bool hasMoreShufflePages;
}

/// Owns the mutable media-list playback state that used to live in
/// [VideoDetailController].
///
/// Network requests and navigation remain in the page controller, while this
/// collaborator is responsible for ordering, shuffled pagination, merging
/// fetched pages, and keeping local playback progress in sync.
final class VideoMediaListCoordinator {
  VideoMediaListCoordinator({Random? random}) : _random = random ?? Random();

  final Random _random;
  final RxList<MediaListItemModel> items = <MediaListItemModel>[].obs;

  ListOrder _order = ListOrder.asc;
  ListOrder get order => _order;

  List<int> _shuffledPages = const [];
  int _shufflePageIndex = 0;
  bool _shufflePagesInitialized = false;
  int _generation = 0;
  int _nextRequestId = 0;
  int? _activeRequestId;

  void setInitialOrder(ListOrder value) {
    _order = value;
    _invalidateRequests();
    _clearShufflePages();
  }

  void invalidate() => _invalidateRequests();

  /// Advances asc -> desc -> shuffle -> asc and resets pagination state for
  /// the newly selected order.
  ListOrder advanceOrder({required int? totalCount}) {
    _order = _order.next;
    _invalidateRequests();
    if (_order.isShuffle) {
      _initializeShufflePages(totalCount);
    } else {
      _clearShufflePages();
    }
    return _order;
  }

  VideoMediaListRequest? beginRequest({
    required int? totalCount,
    required bool isReverse,
    required bool isLoadPrevious,
    required Object playbackIdentity,
  }) {
    if (_activeRequestId != null) return null;
    if (!isReverse &&
        !isLoadPrevious &&
        totalCount != null &&
        items.length >= totalCount) {
      return null;
    }

    final type = isReverse
        ? VideoMediaListLoadType.replace
        : isLoadPrevious
        ? VideoMediaListLoadType.previous
        : VideoMediaListLoadType.next;
    int? page;
    if (_order.isShuffle && !isLoadPrevious) {
      if (!_shufflePagesInitialized) {
        _initializeShufflePages(totalCount);
      }
      if (_shufflePageIndex >= _shuffledPages.length) return null;
      // Reserve without consuming. A failed/empty response can retry the same
      // page instead of silently creating a hole in the shuffle cycle.
      page = _shuffledPages[_shufflePageIndex];
    }

    final request = VideoMediaListRequest._(
      id: ++_nextRequestId,
      generation: _generation,
      order: _order,
      type: type,
      page: page,
      playbackIdentity: playbackIdentity,
    );
    _activeRequestId = request.id;
    return request;
  }

  bool abandonRequest(VideoMediaListRequest request) {
    if (!_isActiveRequest(request)) return false;
    _activeRequestId = null;
    return true;
  }

  bool isRequestGenerationCurrent(VideoMediaListRequest request) =>
      request.generation == _generation && request.order == _order;

  bool isRequestActive(VideoMediaListRequest request) =>
      _isActiveRequest(request);

  bool _isActiveRequest(VideoMediaListRequest request) =>
      request.generation == _generation &&
      request.order == _order &&
      request.id == _activeRequestId;

  void _invalidateRequests() {
    _generation++;
    _activeRequestId = null;
  }

  void _initializeShufflePages(int? totalCount) {
    _shufflePagesInitialized = true;
    _shufflePageIndex = 0;
    if (totalCount == null || totalCount <= 0) {
      _shuffledPages = const [1];
      return;
    }

    final totalPages = (totalCount / 20).ceil();
    _shuffledPages = List<int>.generate(totalPages, (index) => index + 1)
      ..shuffle(_random);

    // Avoid starting with a final page containing only one entry. The media
    // list view triggers load-more near its end, so a one-entry first page can
    // otherwise leave the shuffle cycle unable to request the next page.
    final finalPageItemCount = totalCount - (totalPages - 1) * 20;
    if (totalPages > 1 &&
        _shuffledPages.first == totalPages &&
        finalPageItemCount < 2) {
      final swapIndex = _shuffledPages.indexWhere(
        (page) => page != totalPages,
        1,
      );
      if (swapIndex >= 0) {
        final first = _shuffledPages.first;
        _shuffledPages[0] = _shuffledPages[swapIndex];
        _shuffledPages[swapIndex] = first;
      }
    }
  }

  void _clearShufflePages() {
    _shuffledPages = const [];
    _shufflePageIndex = 0;
    _shufflePagesInitialized = false;
  }

  /// Atomically applies a fetched page. Stale responses are rejected using the
  /// generation/order captured by [beginRequest].
  VideoMediaListApplyResult applyFetchedItems({
    required VideoMediaListRequest request,
    required List<MediaListItemModel> fetched,
    required String currentBvid,
    required Object currentPlaybackIdentity,
  }) {
    if (!_isActiveRequest(request)) {
      return const VideoMediaListApplyResult(accepted: false);
    }
    if (fetched.isEmpty) {
      _commitShufflePage(request);
      _activeRequestId = null;
      return VideoMediaListApplyResult(
        accepted: true,
        hasMoreShufflePages: _hasMoreShufflePages(request),
      );
    }

    late final List<MediaListItemModel> completed;
    if (request.isReverse) {
      completed = _deduplicate(fetched);
      if (request.order.isShuffle) {
        completed.shuffle(_random);
      }
    } else if (request.isLoadPrevious) {
      completed = _deduplicate(<MediaListItemModel>[...fetched, ...items]);
    } else if (request.order.isShuffle) {
      completed = _mergeShuffledAfterCurrent(fetched, currentBvid);
    } else {
      completed = _deduplicate(<MediaListItemModel>[...items, ...fetched]);
    }

    // RxList's mutating helpers can emit an empty/partially updated list and
    // shuffle emits once per swap. Publish the fully built list only once.
    items.value = completed;
    _commitShufflePage(request);
    _activeRequestId = null;

    MediaListItemModel? nextEpisode;
    if (request.isReverse &&
        request.playbackIdentity == currentPlaybackIdentity) {
      for (final item in completed) {
        if (item.cid != null) {
          nextEpisode = item;
          break;
        }
      }
    }
    return VideoMediaListApplyResult(
      accepted: true,
      nextEpisode: nextEpisode,
      hasMoreShufflePages: _hasMoreShufflePages(request),
    );
  }

  void _commitShufflePage(VideoMediaListRequest request) {
    if (request.page != null &&
        _shufflePageIndex < _shuffledPages.length &&
        _shuffledPages[_shufflePageIndex] == request.page) {
      _shufflePageIndex++;
    }
  }

  bool _hasMoreShufflePages(VideoMediaListRequest request) =>
      request.page != null && _shufflePageIndex < _shuffledPages.length;

  List<MediaListItemModel> _mergeShuffledAfterCurrent(
    List<MediaListItemModel> fetched,
    String currentBvid,
  ) {
    final currentIndex = items.indexWhere((item) => item.bvid == currentBvid);
    final tailStart = currentIndex < 0 ? 0 : currentIndex + 1;
    final prefix = items.take(tailStart).toList(growable: false);
    final prefixKeys = prefix.map(_stableIdentity).toSet();
    final shuffledTail = _deduplicate(<MediaListItemModel>[
      ...items.skip(tailStart),
      ...fetched,
    ], excludedKeys: prefixKeys)..shuffle(_random);

    return <MediaListItemModel>[...prefix, ...shuffledTail];
  }

  List<MediaListItemModel> _deduplicate(
    Iterable<MediaListItemModel> source, {
    Set<Object>? excludedKeys,
  }) {
    final values = <Object, MediaListItemModel>{};
    for (final item in source) {
      final key = _stableIdentity(item);
      if (excludedKeys?.contains(key) == true) continue;
      values[key] = item;
    }
    return values.values.toList(growable: true);
  }

  Object _stableIdentity(MediaListItemModel item) {
    final aid = item.aid;
    final bvid = item.bvid;
    if (aid != null && aid > 0) return (type: 'aid', value: aid);
    if (bvid != null && bvid.isNotEmpty) {
      return (type: 'bvid', value: bvid);
    }
    return item;
  }

  bool updateProgress({
    required int videoAid,
    required String videoBvid,
    required int videoCid,
    required int progressSeconds,
    required int videoDuration,
  }) {
    MediaListItemModel? target;
    for (final item in items) {
      if (_matchesItem(item, videoAid, videoBvid, videoCid)) {
        target = item;
        break;
      }
    }
    if (target == null) return false;

    final maxProgress = videoDuration > 0
        ? videoDuration
        : progressSeconds.clamp(0, 0x7fffffff).toInt();
    final newProgress = progressSeconds == -1
        ? -1
        : progressSeconds.clamp(0, maxProgress).toInt();
    if (target.progress == newProgress) return false;
    target.progress = newProgress;
    items.refresh();
    return true;
  }

  bool _matchesItem(
    MediaListItemModel item,
    int videoAid,
    String videoBvid,
    int videoCid,
  ) {
    if (item.aid != videoAid || item.bvid != videoBvid) return false;
    final pages = item.pages;
    if (pages == null || pages.isEmpty) return true;
    return pages.any((page) => page.id == videoCid);
  }

  List<Map<String, int>> buildAudioProgressSnapshot({
    required int currentAid,
    required int currentCid,
    required int? currentProgress,
    required int currentDuration,
  }) {
    final snapshot = <Map<String, int>>[];
    final seen = <String>{};

    void addProgress({
      required int? aid,
      required int? cid,
      required int? progress,
      required int? duration,
    }) {
      if (aid == null || aid <= 0 || cid == null || cid <= 0) return;
      if (progress == null || progress <= 0) return;
      if (!seen.add('$aid:$cid')) return;
      final normalizedProgress = duration != null && duration > 0
          ? progress.clamp(1, duration).toInt()
          : progress;
      snapshot.add({
        'aid': aid,
        'cid': cid,
        'progress': normalizedProgress,
      });
    }

    addProgress(
      aid: currentAid,
      cid: currentCid,
      progress: currentProgress,
      duration: currentDuration,
    );
    for (final item in items) {
      final pages = item.pages;
      if (pages != null && pages.length == 1) {
        addProgress(
          aid: item.aid,
          cid: pages.first.id,
          progress: item.progress,
          duration: item.duration,
        );
      } else if (pages == null || pages.isEmpty) {
        addProgress(
          aid: item.aid,
          cid: item.cid,
          progress: item.progress,
          duration: item.duration,
        );
      }
    }
    return snapshot;
  }

  static int resolveDurationSeconds({
    required int? timeLengthMilliseconds,
    Duration? fallbackDuration,
  }) {
    if (timeLengthMilliseconds != null && timeLengthMilliseconds > 0) {
      return (timeLengthMilliseconds / Duration.millisecondsPerSecond).ceil();
    }
    if (fallbackDuration != null && fallbackDuration > Duration.zero) {
      return fallbackDuration.inSeconds > 0 ? fallbackDuration.inSeconds : 1;
    }
    return 0;
  }

  static int heartBeatProgressSeconds({
    required Duration position,
    required bool isCompleted,
    required int? timeLengthMilliseconds,
  }) {
    if (isCompleted) {
      return -1;
    }
    if (timeLengthMilliseconds != null &&
        timeLengthMilliseconds > 0 &&
        position > Duration.zero) {
      final positionMilliseconds = position.inMilliseconds;
      final remainingMilliseconds =
          timeLengthMilliseconds - positionMilliseconds;
      final playedRatio = positionMilliseconds / timeLengthMilliseconds;
      if (remainingMilliseconds <= Duration.millisecondsPerSecond &&
          playedRatio >= 0.9) {
        return -1;
      }
    }
    return position.inSeconds;
  }
}
