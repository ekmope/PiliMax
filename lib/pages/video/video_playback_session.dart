final class VideoPlaybackIdentity {
  const VideoPlaybackIdentity({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.epId,
    required this.seasonId,
  });

  final int aid;
  final String bvid;
  final int cid;
  final int? epId;
  final int? seasonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoPlaybackIdentity &&
          aid == other.aid &&
          bvid == other.bvid &&
          cid == other.cid &&
          epId == other.epId &&
          seasonId == other.seasonId;

  @override
  int get hashCode => Object.hash(aid, bvid, cid, epId, seasonId);
}

final class VideoPlaybackSessionSnapshot {
  const VideoPlaybackSessionSnapshot._({
    required this.generation,
    required this.identity,
  });

  final int generation;
  final VideoPlaybackIdentity identity;
}

final class VideoPlaybackSession {
  int _generation = 0;
  Future<void> _sourceSwitchQueue = Future<void>.value();

  VideoPlaybackSessionSnapshot begin(VideoPlaybackIdentity identity) {
    return VideoPlaybackSessionSnapshot._(
      generation: ++_generation,
      identity: identity,
    );
  }

  void invalidate() {
    _generation++;
  }

  bool isCurrent(
    VideoPlaybackSessionSnapshot snapshot, {
    required bool Function() isActive,
    required VideoPlaybackIdentity Function() currentIdentity,
    bool Function()? additionalValidity,
  }) {
    return isActive() &&
        snapshot.generation == _generation &&
        snapshot.identity == currentIdentity() &&
        (additionalValidity?.call() ?? true);
  }

  Future<void> enqueueSourceSwitch(
    VideoPlaybackSessionSnapshot snapshot, {
    required bool Function() isActive,
    required VideoPlaybackIdentity Function() currentIdentity,
    bool Function()? additionalValidity,
    required Future<void> Function() action,
  }) {
    final run = _sourceSwitchQueue.then((_) async {
      if (!isCurrent(
        snapshot,
        isActive: isActive,
        currentIdentity: currentIdentity,
        additionalValidity: additionalValidity,
      )) {
        return;
      }
      await action();
    });
    _sourceSwitchQueue = run.catchError((_) {});
    return run;
  }
}
