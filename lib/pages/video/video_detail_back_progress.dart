import 'package:flutter/foundation.dart';

const videoDetailBackProgressKey = '_videoDetailBackProgress';

enum VideoDetailBackPhase {
  idle,
  predicting,
  canceling,
  committing,
  programmatic,
  dismissed,
}

final class VideoDetailBackSnapshot {
  const VideoDetailBackSnapshot({
    required this.phase,
    required this.exitProgress,
    required this.routeValue,
    required this.sourceHandoff,
    required this.hasSourceTarget,
  });

  const VideoDetailBackSnapshot.idle()
    : phase = VideoDetailBackPhase.idle,
      exitProgress = 0,
      routeValue = 1,
      sourceHandoff = 0,
      hasSourceTarget = false;

  final VideoDetailBackPhase phase;

  /// Zero is the full detail page; one is the source card.
  final double exitProgress;

  /// The raw route animation value: one is current, zero is dismissed.
  final double routeValue;

  /// Complementary handoff progress for the source card near exit completion.
  final double sourceHandoff;

  final bool hasSourceTarget;

  double get entryProgress => 1 - exitProgress;

  /// Timeline used when handing copied source decorations back to the live
  /// card. Programmatic reversal preserves the unfinished push timeline;
  /// gesture-driven motion follows the published visual geometry.
  double get sourcePresentationProgress =>
      phase == VideoDetailBackPhase.programmatic ? routeValue : entryProgress;

  bool get isGestureDriven => phase == VideoDetailBackPhase.predicting;

  @override
  bool operator ==(Object other) =>
      other is VideoDetailBackSnapshot &&
      other.phase == phase &&
      other.exitProgress == exitProgress &&
      other.routeValue == routeValue &&
      other.sourceHandoff == sourceHandoff &&
      other.hasSourceTarget == hasSourceTarget;

  @override
  int get hashCode => Object.hash(
    phase,
    exitProgress,
    routeValue,
    sourceHandoff,
    hasSourceTarget,
  );
}

typedef VideoDetailBackProgressListener = VoidCallback;

abstract interface class VideoDetailBackProgress implements Listenable {
  VideoDetailBackSnapshot get value;

  @override
  void addListener(VideoDetailBackProgressListener listener);

  @override
  void removeListener(VideoDetailBackProgressListener listener);
}

final class VideoDetailBackProgressController
    implements VideoDetailBackProgress {
  VideoDetailBackSnapshot _value = const VideoDetailBackSnapshot.idle();
  final Set<VideoDetailBackProgressListener> _listeners = {};
  int _ownerCount = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  VideoDetailBackProgressController retain() {
    if (_disposed) {
      throw StateError('Cannot retain a disposed back-progress controller.');
    }
    _ownerCount += 1;
    return this;
  }

  void release() {
    if (_ownerCount == 0) {
      return;
    }
    _ownerCount -= 1;
    if (_ownerCount == 0) {
      _dispose();
    }
  }

  @override
  VideoDetailBackSnapshot get value => _value;

  @override
  void addListener(VideoDetailBackProgressListener listener) {
    if (!_disposed) {
      _listeners.add(listener);
    }
  }

  @override
  void removeListener(VideoDetailBackProgressListener listener) {
    _listeners.remove(listener);
  }

  void update({
    required VideoDetailBackPhase phase,
    required double exitProgress,
    required double routeValue,
    required double sourceHandoff,
    required bool hasSourceTarget,
  }) {
    if (_disposed) {
      return;
    }
    final next = VideoDetailBackSnapshot(
      phase: phase,
      exitProgress: exitProgress.clamp(0.0, 1.0).toDouble(),
      routeValue: routeValue.clamp(0.0, 1.0).toDouble(),
      sourceHandoff: sourceHandoff.clamp(0.0, 1.0).toDouble(),
      hasSourceTarget: hasSourceTarget,
    );
    if (next == _value) {
      return;
    }
    _value = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _listeners.clear();
  }
}

VideoDetailBackProgressController ensureVideoDetailBackProgress(
  Map<dynamic, dynamic> arguments,
) {
  final existing = arguments[videoDetailBackProgressKey];
  if (existing is VideoDetailBackProgressController && !existing.isDisposed) {
    return existing;
  }
  final controller = VideoDetailBackProgressController();
  arguments[videoDetailBackProgressKey] = controller;
  return controller;
}
