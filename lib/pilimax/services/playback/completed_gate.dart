import 'dart:async';

class CompletedGate {
  const CompletedGate._();

  static const Duration maxRemaining = Duration(milliseconds: 1200);
  static const Duration readyRemaining = Duration(milliseconds: 100);
  static const Duration buffer = Duration(milliseconds: 200);

  static Duration? remaining({
    required Duration total,
    required Duration position,
    Duration maxAllowed = maxRemaining,
  }) {
    if (total <= Duration.zero) {
      return null;
    }
    final remaining = total - position;
    if (remaining > maxAllowed) {
      return null;
    }
    return remaining <= Duration.zero ? Duration.zero : remaining;
  }

  static bool isReady(Duration remaining) => remaining <= readyRemaining;

  static Duration? longer(Duration? a, Duration? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a >= b ? a : b;
  }

  static Duration tailPlaybackWait(
    Duration remaining, {
    required double playbackRate,
  }) {
    final rate = playbackRate > 0 ? playbackRate : 1.0;
    final playbackMs = remaining.inMilliseconds / rate;
    return Duration(milliseconds: playbackMs.ceil());
  }

  static Duration tailWait(
    Duration remaining, {
    required double playbackRate,
  }) => tailPlaybackWait(remaining, playbackRate: playbackRate) + buffer;

  static Duration delay(Duration remaining) => remaining + buffer;
}

class CompletedGateScheduler {
  Timer? _timer;
  int _token = 0;

  bool cancel() {
    final hadPending = _timer != null;
    _token += 1;
    _timer?.cancel();
    _timer = null;
    return hadPending;
  }

  void schedule(Duration delay, void Function() onFire) {
    final token = ++_token;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (token != _token) {
        return;
      }
      _timer = null;
      onFire();
    });
  }
}
