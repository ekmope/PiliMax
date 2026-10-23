/// Tracks whether a PiP replacement may uncover the incoming detail player.
///
/// The incoming poster remains visible until its player reports a usable
/// visual frame. If that signal is delayed, the captured PiP frame can still
/// complete its flight into the poster instead of exposing an empty surface.
final class PipReplacementTransitionState {
  PipReplacementTransitionState({required this.hasSnapshot});

  final bool hasSnapshot;
  bool _playerVisualReady = false;
  bool _fallbackElapsed = false;

  bool get playerVisualReady => _playerVisualReady;

  bool get shouldShowIncomingCover =>
      !_playerVisualReady && (!hasSnapshot || _fallbackElapsed);

  bool get shouldFadeSnapshot => _playerVisualReady || _fallbackElapsed;

  double get incomingCoverOpacity => _playerVisualReady ? 0 : 1;

  void markPlayerVisualReady() => _playerVisualReady = true;

  void markFallbackElapsed() => _fallbackElapsed = true;
}
