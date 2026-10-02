import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/pages/home/controller.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  RxDouble? _barOffset;
  RxBool? _showTopBar;
  RxBool? _showBottomBar;
  double _accumulatedScroll = 0;
  final _mainController = Get.find<MainController>();

  bool get needsCorrection => false;

  @override
  void initState() {
    super.initState();
    _barOffset = _mainController.barOffset;
    _showBottomBar = _mainController.showBottomBar;
    try {
      _showTopBar = Get.find<HomeController>().showTopBar;
    } catch (_) {}
  }

  Widget onBuild(Widget child) {
    if (_barOffset != null) {
      return NotificationListener<ScrollNotification>(
        onNotification: onNotificationType2,
        child: child,
      );
    }
    if (_showTopBar != null || _showBottomBar != null) {
      return NotificationListener<ScrollNotification>(
        onNotification: onNotificationType1,
        child: child,
      );
    }
    return child;
  }

  // Hide/show with distance thresholds and hysteresis: scrolling down must
  // accumulate 24 dp to collapse the bars, while 12 dp back up expands
  // them, so slow jitter cannot toggle the bars repeatedly.
  bool onNotificationType1(ScrollNotification notification) {
    if (!_mainController.useBottomNav) return false;
    if (notification.metrics.axis == .horizontal) return false;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      _mainController.navScrollVelocity.value = clampDouble(
        delta / 18,
        -1.0,
        1.0,
      );
      if ((delta > 0 && _accumulatedScroll < 0) ||
          (delta < 0 && _accumulatedScroll > 0)) {
        _accumulatedScroll = 0;
      }
      _accumulatedScroll += delta;
      if (_accumulatedScroll >= 24) {
        _showTopBar?.value = false;
        _showBottomBar?.value = false;
      } else if (_accumulatedScroll <= -12) {
        _showTopBar?.value = true;
        _showBottomBar?.value = true;
      }
    } else if (notification is ScrollEndNotification) {
      _accumulatedScroll = 0;
      _mainController.navScrollVelocity.value = 0;
    }
    return false;
  }

  void _updateOffset(double scrollDelta) {
    _barOffset!.value = clampDouble(
      _barOffset!.value + scrollDelta,
      0.0,
      Style.topBarHeight,
    );
  }

  bool onNotificationType2(ScrollNotification notification) {
    if (!_mainController.useBottomNav) return false;

    final metrics = notification.metrics;
    if (metrics.axis == .horizontal) return false;

    if (notification is ScrollStartNotification) {
      _mainController.cancelBarOffsetSettle();
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) return false;
      final pixel = metrics.pixels;
      final scrollDelta = notification.scrollDelta ?? 0;
      _mainController.navScrollVelocity.value = clampDouble(
        scrollDelta / 18,
        -1.0,
        1.0,
      );
      if (pixel < 0.0 && scrollDelta > 0) return false;
      if (needsCorrection) {
        final value = _barOffset!.value;
        final newValue = clampDouble(
          value + scrollDelta,
          0.0,
          Style.topBarHeight,
        );
        final offset = value - newValue;
        if (offset != 0) {
          _barOffset!.value = newValue;
          if (pixel < 0.0 && scrollDelta < 0.0 && value > 0.0) {
            return false;
          }
          Scrollable.of(notification.context!).position.correctBy(offset);
        }
      } else {
        _updateOffset(scrollDelta);
      }
      return false;
    }

    if (notification is OverscrollNotification) {
      _mainController.navScrollVelocity.value = clampDouble(
        notification.overscroll / 18,
        -1.0,
        1.0,
      );
      _updateOffset(notification.overscroll);
      return false;
    }

    if (notification is ScrollEndNotification) {
      _mainController.navScrollVelocity.value = 0;
      _mainController.settleBarOffset();
      return false;
    }

    return false;
  }

  @override
  void dispose() {
    _barOffset = null;
    _showTopBar = null;
    _showBottomBar = null;
    super.dispose();
  }
}
