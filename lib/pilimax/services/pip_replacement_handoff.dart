import 'dart:async';
import 'dart:ui' as ui;

/// Owns the one-frame visual handoff used when PiP is replaced by another
/// video detail route. The handoff deliberately stores an image instead of a
/// second player surface, so the new route remains the only active texture.
abstract final class PipReplacementHandoff {
  static PipReplacementFrame? _frame;
  static Timer? _expiryTimer;

  static bool get hasFrame => _frame != null;

  static void publish(ui.Image image, ui.Rect sourceRect) {
    final previous = _frame;
    _frame = PipReplacementFrame(image: image, sourceRect: sourceRect);
    previous?.image.dispose();
    _expiryTimer?.cancel();
    _expiryTimer = Timer(const Duration(seconds: 8), clear);
  }

  static PipReplacementFrame? take() {
    final frame = _frame;
    _frame = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    return frame;
  }

  static void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final frame = _frame;
    _frame = null;
    frame?.image.dispose();
  }
}

final class PipReplacementFrame {
  const PipReplacementFrame({required this.image, required this.sourceRect});

  final ui.Image image;
  final ui.Rect sourceRect;
}
