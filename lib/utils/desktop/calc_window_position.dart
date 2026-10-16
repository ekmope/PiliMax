import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/extension/native_geometry_ext.dart';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show Offset, Size;
import 'package:nativeapi/nativeapi.dart' as nativeapi;

const _displayManager = nativeapi.DisplayManager.instance;

nativeapi.Rectangle calcWindowBounds() {
  final windowSize = Pref.windowSize;
  final position = calcWindowPosition(windowSize);
  return nativeapi.Rectangle(
    x: position.dx,
    y: position.dy,
    width: windowSize.width,
    height: windowSize.height,
  );
}

Offset calcWindowPosition(Size windowSize) {
  final displays = _displayManager.getAll();
  final cursorPosition = _displayManager.getCursorPosition().toOffset();
  final display =
      displays.firstWhereOrNull(
        (item) => (item.position.toOffset() & item.size.toSize()).contains(
          cursorPosition,
        ),
      ) ??
      _displayManager.getPrimary();
  if (display == null) return Offset.zero;

  final workArea = display.workArea.toRect();
  final savedPosition = Pref.windowPosition;
  if (savedPosition != null) {
    try {
      final left = workArea.left;
      final top = workArea.top;
      final right = left + workArea.width - 30;
      final bottom = top + workArea.height - 30;
      final dx = savedPosition[0];
      final dy = savedPosition[1];
      if (dx >= left && dy >= top && dx < right && dy < bottom) {
        return Offset(dx, dy);
      }
    } catch (_) {}
  }

  return Offset(
    workArea.left + (workArea.width - windowSize.width) / 2,
    workArea.top + (workArea.height - windowSize.height) / 2,
  );
}
