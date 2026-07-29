import 'dart:async';

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Offset, Rect;
import 'package:flutter/scheduler.dart';

/// In-app PiP lifecycle states.
enum PipPhase { hidden, entering, active, restoring }

/// Session-scoped PiP window placement shared by video and live overlays.
class PipWindowMemory {
  PipWindowMemory._();

  static Offset? position;
  static double scale = 1.0;
}

/// Coordinates PiP shrink and restore animations without owning a player.
class PipTransitionCoordinator extends ChangeNotifier {
  static const Duration animDuration = Duration(milliseconds: 300);
  static const Duration closeFadeDuration = Duration(milliseconds: 180);
  static const Curve animCurve = Curves.easeOutCubic;
  static const Duration _restoreAttachTimeout = Duration(seconds: 2);

  PipPhase _phase = PipPhase.hidden;
  PipPhase get phase => _phase;

  Rect? _sourceRect;
  Rect? get sourceRect => _sourceRect;

  Rect? _restoreTargetRect;
  VoidCallback? _onRestorePageReady;
  bool _restoreAnimationDone = false;
  Timer? _restoreTimer;

  VoidCallback? onRestoreFinished;

  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  void beginEnter({Rect? sourceRect}) {
    _cancelRestoreHandshake();
    _sourceRect = sourceRect;
    _phase = sourceRect == null ? PipPhase.active : PipPhase.entering;
    _notify();
  }

  void markEnterDone() {
    if (_phase != PipPhase.entering) return;
    _phase = PipPhase.active;
    _notify();
  }

  bool beginRestore() {
    switch (_phase) {
      case PipPhase.hidden:
        return false;
      case PipPhase.restoring:
        return true;
      case PipPhase.entering:
        _phase = PipPhase.active;
      case PipPhase.active:
        break;
    }

    _restoreAnimationDone = false;
    _onRestorePageReady = null;
    _restoreTargetRect = _sourceRect;
    _phase = PipPhase.restoring;
    _restoreTimer?.cancel();
    _restoreTimer = Timer(_restoreAttachTimeout, _onRestoreTimeout);
    _notify();
    return true;
  }

  void attachRestorePage({
    Rect? targetRect,
    required VoidCallback onCompleted,
  }) {
    if (_phase != PipPhase.restoring) {
      onCompleted();
      return;
    }

    _restoreTimer?.cancel();
    _restoreTimer = null;
    if (targetRect != null && targetRect != _restoreTargetRect) {
      _restoreTargetRect = targetRect;
      _notify();
    }
    _onRestorePageReady = onCompleted;
    _tryFinishRestore();
  }

  void markRestoreAnimationDone() {
    if (_phase != PipPhase.restoring) return;
    _restoreAnimationDone = true;
    _tryFinishRestore();
  }

  void _tryFinishRestore() {
    if (_phase != PipPhase.restoring ||
        !_restoreAnimationDone ||
        _onRestorePageReady == null) {
      return;
    }

    final pageReady = _onRestorePageReady;
    _cancelRestoreHandshake();
    _phase = PipPhase.hidden;
    onRestoreFinished?.call();
    pageReady?.call();
    _notify();
  }

  void _onRestoreTimeout() {
    if (_phase != PipPhase.restoring || _onRestorePageReady != null) return;
    _cancelRestoreHandshake();
    _phase = PipPhase.active;
    _notify();
  }

  void reset() {
    _cancelRestoreHandshake();
    _sourceRect = null;
    _phase = PipPhase.hidden;
    _notify();
  }

  void _cancelRestoreHandshake() {
    _restoreTimer?.cancel();
    _restoreTimer = null;
    _onRestorePageReady = null;
    _restoreAnimationDone = false;
    _restoreTargetRect = null;
  }

  Rect resolveRect({required Rect miniRect, required double progress}) {
    return switch (_phase) {
      PipPhase.entering => Rect.lerp(
        _sourceRect ?? miniRect,
        miniRect,
        progress,
      )!,
      PipPhase.restoring => Rect.lerp(
        miniRect,
        _restoreTargetRect ?? miniRect,
        progress,
      )!,
      _ => miniRect,
    };
  }

  double resolveRadius({required double base, required double progress}) {
    return switch (_phase) {
      PipPhase.entering => base * progress,
      PipPhase.restoring => base * (1 - progress),
      _ => base,
    };
  }
}
