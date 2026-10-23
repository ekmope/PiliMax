import 'package:PiliMax/pilimax/services/pip_replacement_transition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the incoming cover until the player is visually ready', () {
    final transition = PipReplacementTransitionState(hasSnapshot: true);

    expect(transition.shouldShowIncomingCover, isFalse);
    expect(transition.shouldFadeSnapshot, isFalse);

    transition.markFallbackElapsed();

    expect(transition.shouldShowIncomingCover, isTrue);
    expect(transition.shouldFadeSnapshot, isTrue);

    transition.markPlayerVisualReady();

    expect(transition.shouldShowIncomingCover, isFalse);
    expect(transition.shouldFadeSnapshot, isTrue);
  });

  test('without a snapshot, the cover waits for a real player frame', () {
    final transition = PipReplacementTransitionState(hasSnapshot: false);

    expect(transition.shouldShowIncomingCover, isTrue);
    transition.markPlayerVisualReady();

    expect(transition.shouldShowIncomingCover, isFalse);
    expect(transition.shouldFadeSnapshot, isTrue);
  });
}
