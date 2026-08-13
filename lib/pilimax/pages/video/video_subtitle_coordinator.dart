import 'package:PiliMax/models_new/video/video_play_info/subtitle.dart';

typedef VideoSubtitleSource = ({bool isData, String id});
typedef VideoSubtitleLoader = Future<String?> Function(String subtitleUrl);

final class VideoSubtitleContext {
  const VideoSubtitleContext({
    required this.bvid,
    required this.cid,
    required this.epId,
    required this.seasonId,
  });

  final String bvid;
  final int cid;
  final int? epId;
  final int? seasonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoSubtitleContext &&
          bvid == other.bvid &&
          cid == other.cid &&
          epId == other.epId &&
          seasonId == other.seasonId;

  @override
  int get hashCode => Object.hash(bvid, cid, epId, seasonId);
}

final class VideoSubtitleContextLease {
  const VideoSubtitleContextLease._({
    required this.generation,
    required this.context,
  });

  final int generation;
  final VideoSubtitleContext context;
}

final class VideoSubtitleTrack {
  const VideoSubtitleTrack({
    required this.uri,
    required this.language,
    required this.label,
  });

  final String uri;
  final String language;
  final String? label;
}

/// Minimal player boundary used by subtitle selection. The concrete media-kit
/// adapter stays in the page controller while this coordinator remains
/// independently testable.
abstract interface class VideoSubtitlePlayer {
  Object get identity;

  Future<void> setPrimarySubtitle(VideoSubtitleTrack? track);

  Future<void> setSecondarySubtitle(VideoSubtitleTrack? track);
}

/// Serializes mutations of the singleton player's two subtitle tracks across
/// every video page. Each page owns its own [VideoSubtitleCoordinator], but all
/// production coordinators share one instance of this executor.
final class VideoSubtitleSharedState {
  Future<void> _trackUpdateQueue = Future<void>.value();

  int appliedPrimaryIndex = 0;
  int appliedSecondaryIndex = 0;

  Future<void> enqueue(Future<void> Function() action) {
    final run = _trackUpdateQueue.then((_) => action());
    _trackUpdateQueue = run.catchError((_) {});
    return run;
  }
}

/// Owns subtitle selection generations, VTT resolution races, track mutation
/// serialization and primary/secondary conflict arbitration.
final class VideoSubtitleCoordinator {
  VideoSubtitleCoordinator({
    required this.subtitles,
    required this.sources,
    required this.primaryIndex,
    required this.setPrimaryIndex,
    required this.secondaryIndex,
    required this.setSecondaryIndex,
    required this.currentContext,
    required this.isCurrentSource,
    required this.playerProvider,
    required this.loadVtt,
    VideoSubtitleSharedState? sharedState,
  }) : _sharedState = sharedState ?? _defaultSharedState;

  static final VideoSubtitleSharedState _defaultSharedState =
      VideoSubtitleSharedState();

  final List<Subtitle> Function() subtitles;
  final Map<int, VideoSubtitleSource> sources;
  final int Function() primaryIndex;
  final void Function(int value) setPrimaryIndex;
  final int Function() secondaryIndex;
  final void Function(int value) setSecondaryIndex;
  final VideoSubtitleContext Function() currentContext;
  final bool Function() isCurrentSource;
  final VideoSubtitlePlayer? Function() playerProvider;
  final VideoSubtitleLoader loadVtt;
  final VideoSubtitleSharedState _sharedState;

  int _contextGeneration = 0;
  int _primarySelectionGeneration = 0;
  int _secondarySelectionGeneration = 0;
  int? _pendingPrimaryIndex;
  int? _pendingSecondaryIndex;

  VideoSubtitleContextLease captureContext() => VideoSubtitleContextLease._(
    generation: _contextGeneration,
    context: currentContext(),
  );

  bool isCurrentContext(VideoSubtitleContextLease lease) =>
      isCurrentSource() &&
      lease.generation == _contextGeneration &&
      lease.context == currentContext();

  void invalidate() {
    _contextGeneration++;
    _primarySelectionGeneration++;
    _secondarySelectionGeneration++;
    _pendingPrimaryIndex = null;
    _pendingSecondaryIndex = null;
  }

  Future<void> selectPrimary(int index) async {
    final selectionGeneration = ++_primarySelectionGeneration;
    final context = captureContext();
    bool isCurrent() =>
        selectionGeneration == _primarySelectionGeneration &&
        isCurrentContext(context);
    _pendingPrimaryIndex = null;

    if (index <= 0) {
      _pendingPrimaryIndex = 0;
      try {
        await _sharedState.enqueue(() async {
          if (!isCurrent()) return;
          final player = playerProvider();
          if (player == null) {
            _sharedState.appliedPrimaryIndex = 0;
            return;
          }
          await player.setPrimarySubtitle(null);
          if (isCurrent() && _isSamePlayer(player)) {
            _sharedState.appliedPrimaryIndex = 0;
          }
        });
        _reconcilePrimary(isCurrent, loadingIndex: index);
      } catch (_) {
        _reconcilePrimary(isCurrent, loadingIndex: index);
        rethrow;
      } finally {
        if (selectionGeneration == _primarySelectionGeneration) {
          _pendingPrimaryIndex = null;
        }
      }
      return;
    }

    final subIndex = index - 1;
    final availableSubtitles = subtitles();
    if (subIndex < 0 || subIndex >= availableSubtitles.length) {
      _reconcilePrimary(isCurrent);
      return;
    }
    final subtitle = availableSubtitles[subIndex];
    _pendingPrimaryIndex = index;
    try {
      if (_secondaryConflicts(index)) {
        await selectSecondary(0);
        if (!isCurrent()) return;
      }

      final uri = await _resolveVttUri(
        subIndex: subIndex,
        subtitle: subtitle,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return;
      if (uri == null) {
        _reconcilePrimary(isCurrent);
        return;
      }

      // A secondary selection may have changed while VTT was loading.
      if (_secondaryConflicts(index)) {
        await selectSecondary(0);
        if (!isCurrent()) return;
      }

      await _sharedState.enqueue(() async {
        if (!isCurrent() || _secondaryConflictsForQueuedPrimary(index)) {
          return;
        }
        final player = playerProvider();
        if (player == null) return;
        await player.setPrimarySubtitle(
          VideoSubtitleTrack(
            uri: uri,
            language: subtitle.lan,
            label: subtitle.lanDoc,
          ),
        );
        if (!isCurrent() || !_isSamePlayer(player)) return;
        _sharedState.appliedPrimaryIndex = index;
      });
      await _clearAppliedSecondaryConflict(isCurrent);
      _reconcilePrimary(isCurrent);
      _reconcileSecondary(isCurrent);
    } catch (_) {
      _reconcilePrimary(isCurrent);
      _reconcileSecondary(isCurrent);
      rethrow;
    } finally {
      if (selectionGeneration == _primarySelectionGeneration) {
        _pendingPrimaryIndex = null;
      }
    }
  }

  Future<void> selectSecondary(int index) async {
    final selectionGeneration = ++_secondarySelectionGeneration;
    final context = captureContext();
    bool isCurrent() =>
        selectionGeneration == _secondarySelectionGeneration &&
        isCurrentContext(context);
    _pendingSecondaryIndex = null;

    // A track cannot be primary and secondary at the same time. Primary wins.
    if (index <= 0 || _primaryConflicts(index)) {
      _pendingSecondaryIndex = 0;
      try {
        await _sharedState.enqueue(() async {
          if (!isCurrent()) return;
          final player = playerProvider();
          if (player == null) {
            _sharedState.appliedSecondaryIndex = 0;
            return;
          }
          await player.setSecondarySubtitle(null);
          if (isCurrent() && _isSamePlayer(player)) {
            _sharedState.appliedSecondaryIndex = 0;
          }
        });
        _reconcileSecondary(isCurrent);
      } catch (_) {
        _reconcileSecondary(isCurrent);
        rethrow;
      } finally {
        if (selectionGeneration == _secondarySelectionGeneration) {
          _pendingSecondaryIndex = null;
        }
      }
      return;
    }

    final subIndex = index - 1;
    final availableSubtitles = subtitles();
    if (subIndex < 0 || subIndex >= availableSubtitles.length) {
      _reconcileSecondary(isCurrent);
      return;
    }
    final subtitle = availableSubtitles[subIndex];
    _pendingSecondaryIndex = index;
    if (playerProvider() == null) {
      _pendingSecondaryIndex = null;
      _reconcileSecondary(isCurrent);
      return;
    }

    try {
      final uri = await _resolveVttUri(
        subIndex: subIndex,
        subtitle: subtitle,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return;
      if (uri == null) {
        _reconcileSecondary(isCurrent);
        return;
      }

      if (_primaryConflicts(index)) {
        await selectSecondary(0);
        return;
      }

      await _sharedState.enqueue(() async {
        if (!isCurrent() || _primaryConflicts(index)) return;
        final player = playerProvider();
        if (player == null) return;
        await player.setSecondarySubtitle(
          VideoSubtitleTrack(
            uri: uri,
            language: subtitle.lan,
            label: subtitle.lanDoc,
          ),
        );
        if (!isCurrent() || !_isSamePlayer(player)) return;
        _sharedState.appliedSecondaryIndex = index;
      });
      await _clearAppliedSecondaryConflict(isCurrent);
      _reconcilePrimary(isCurrent);
      _reconcileSecondary(isCurrent);
    } catch (_) {
      _reconcilePrimary(isCurrent);
      _reconcileSecondary(isCurrent);
      rethrow;
    } finally {
      if (selectionGeneration == _secondarySelectionGeneration) {
        _pendingSecondaryIndex = null;
      }
    }
  }

  bool _secondaryConflicts(int index) =>
      index == secondaryIndex() ||
      index == _pendingSecondaryIndex ||
      index == _sharedState.appliedSecondaryIndex;

  bool _secondaryConflictsForQueuedPrimary(int index) {
    final pending = _pendingSecondaryIndex;
    return pending == index ||
        (secondaryIndex() == index && pending != 0) ||
        (_sharedState.appliedSecondaryIndex == index && pending != 0);
  }

  bool _primaryConflicts(int index) =>
      index == primaryIndex() ||
      index == _pendingPrimaryIndex ||
      index == _sharedState.appliedPrimaryIndex;

  Future<void> _clearAppliedSecondaryConflict(
    bool Function() isCurrent,
  ) => _sharedState.enqueue(() async {
    if (!isCurrent() ||
        _sharedState.appliedPrimaryIndex <= 0 ||
        _sharedState.appliedPrimaryIndex !=
            _sharedState.appliedSecondaryIndex) {
      return;
    }
    final player = playerProvider();
    if (player == null) {
      _sharedState.appliedSecondaryIndex = 0;
    } else {
      await player.setSecondarySubtitle(null);
      if (!isCurrent() || !_isSamePlayer(player)) return;
      _sharedState.appliedSecondaryIndex = 0;
    }
    if (isCurrent()) {
      setSecondaryIndex(0);
    }
  });

  Future<String?> _resolveVttUri({
    required int subIndex,
    required Subtitle subtitle,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    VideoSubtitleSource? resolved = sources[subIndex];
    if (resolved == null) {
      final subtitleUrl = subtitle.subtitleUrl;
      if (subtitleUrl == null) return null;
      final result = await loadVtt(subtitleUrl);
      if (!isCurrent() || result == null) return null;
      resolved = (isData: true, id: result);
      sources[subIndex] = resolved;
    }
    return resolved.isData ? 'memory://${resolved.id}' : resolved.id;
  }

  void _reconcilePrimary(
    bool Function() isCurrent, {
    int? loadingIndex,
  }) {
    if (!isCurrent()) return;
    setPrimaryIndex(
      loadingIndex != null && loadingIndex < 0
          ? loadingIndex
          : _sharedState.appliedPrimaryIndex,
    );
  }

  void _reconcileSecondary(bool Function() isCurrent) {
    if (isCurrent()) {
      setSecondaryIndex(_sharedState.appliedSecondaryIndex);
    }
  }

  bool _isSamePlayer(VideoSubtitlePlayer player) {
    final current = playerProvider();
    return current != null && identical(current.identity, player.identity);
  }
}
