import 'dart:async' show Timer;
import 'dart:io' show Platform;

import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/utils/desktop/tray_controller.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:window_manager/window_manager.dart';

class WindowController {
  WindowController._();

  static WindowController get instance => _instance;
  static final WindowController _instance = WindowController._();

  nativeapi.Window? _window;
  nativeapi.Window? get window => _window;
  int? _windowListenerId;
  double? _opacity;
  bool _isMaximized = false;

  final _setting = GStorage.setting;
  Timer? _moveTimer;
  Timer? _resizeTimer;
  static const _debounce = Duration(milliseconds: 200);

  late final bool showTrayIcon = Pref.showTrayIcon;
  late bool minimizeOnExit = Pref.minimizeOnExit;
  late bool pauseOnMinimize = Pref.pauseOnMinimize;
  late bool isPlaying = false;

  void init() {
    assert(_window == null);
    final window = WindowManager.instance.getCurrent();
    if (window == null) return;
    _window = window;
    _windowListenerId = window.addListener(_onWindowEvent);
    _isMaximized = window.isMaximized;
  }

  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowFocusedEvent():
        _setOpacity(1);
      case WindowMinimizedEvent():
        _pauseIfNeeded();
      case WindowMaximizedEvent():
        _setting.put(SettingBoxKey.isWindowMaximized, _isMaximized = true);
      case WindowRestoredEvent():
        if (_isMaximized) {
          _setting.put(SettingBoxKey.isWindowMaximized, _isMaximized = false);
        }
        _playIfNeeded();
      case WindowMovedEvent():
        _moveTimer?.cancel();
        _moveTimer = Timer(_debounce, _savePosition);
      case WindowResizedEvent():
        _resizeTimer?.cancel();
        _resizeTimer = Timer(_debounce, _saveBounds);
      case WindowCloseRequestedEvent():
        event.request.cancel();
        if (showTrayIcon && minimizeOnExit) {
          hide();
        } else {
          onClose();
        }
      case WindowBlurredEvent() ||
          WindowCreatedEvent() ||
          WindowClosedEvent() ||
          WindowEnteredFullScreenEvent() ||
          WindowExitedFullScreenEvent() ||
          WindowPropertyChangedEvent() ||
          WindowOcclusionChangedEvent():
        break;
    }
  }

  void _savePosition() {
    final window = _window;
    if (window == null ||
        (PlPlayerController.instance?.updatePipBounds(window) ?? false)) {
      return;
    }
    final position = window.position;
    _setting.put(SettingBoxKey.windowPosition, [position.x, position.y]);
  }

  void _saveBounds() {
    final window = _window;
    if (window == null ||
        (PlPlayerController.instance?.updatePipBounds(window) ?? false)) {
      return;
    }
    final bounds = window.bounds;
    _setting.putAll({
      SettingBoxKey.windowSize: [bounds.width, bounds.height],
      SettingBoxKey.windowPosition: [bounds.x, bounds.y],
    });
  }

  void _pauseIfNeeded() {
    if (!pauseOnMinimize) return;
    final player = PlPlayerController.instance;
    if (player == null) {
      isPlaying = false;
    } else if (!isPlaying && player.playerStatus.value.isPlaying) {
      isPlaying = true;
      player.pause();
    }
  }

  void _playIfNeeded() {
    final shouldResume = pauseOnMinimize && isPlaying;
    isPlaying = false;
    if (shouldResume) PlPlayerController.instance?.play();
  }

  Future<void> onClose() async {
    await GStorage.compact();
    await GStorage.close();
    TrayController.instance.dispose();
    DeviceUtils.exitApp();
  }

  void _setOpacity(double opacity) {
    if (Platform.isWindows && _opacity != opacity) {
      _opacity = opacity;
      _window?.opacity = opacity;
    }
  }

  void hide() {
    _pauseIfNeeded();
    _setOpacity(0);
    _window?.hide();
  }

  void show() {
    _setOpacity(1);
    _window
      ?..focus()
      ..show();
    _playIfNeeded();
  }

  void toggleVisibility() {
    final window = _window;
    if (window == null) return;
    if (window.isVisible) {
      hide();
    } else {
      show();
    }
  }

  void dispose() {
    _moveTimer?.cancel();
    _resizeTimer?.cancel();
    final window = _window;
    final listenerId = _windowListenerId;
    if (window != null && listenerId != null) {
      window.removeListener(listenerId);
    }
    _windowListenerId = null;
    _window = null;
  }
}
