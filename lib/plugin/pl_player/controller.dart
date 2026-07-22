import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:convert' show ascii, utf8;
import 'dart:io' show Platform;
import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/http/browser_ua.dart';
import 'package:PiliMax/http/constants.dart';
import 'package:PiliMax/http/loading_state.dart' show LoadingState, Success;
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/models/common/audio_normalization.dart';
import 'package:PiliMax/models/common/dm_chart_source.dart';
import 'package:PiliMax/models/common/super_resolution_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/user/danmaku_rule.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/video/video_shot/data.dart';
import 'package:PiliMax/pages/danmaku/danmaku_model.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/pages/setting/models/play_settings.dart'
    show kMaxVolume;
import 'package:PiliMax/pages/sponsor_block/block_mixin.dart';
import 'package:PiliMax/plugin/pl_player/models/data_source.dart';
import 'package:PiliMax/plugin/pl_player/models/data_status.dart';
import 'package:PiliMax/plugin/pl_player/models/double_tap_type.dart';
import 'package:PiliMax/plugin/pl_player/models/duration.dart';
import 'package:PiliMax/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliMax/plugin/pl_player/models/heart_beat_type.dart';
import 'package:PiliMax/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliMax/plugin/pl_player/pl_player_source_coordinator.dart';
import 'package:PiliMax/plugin/pl_player/pl_player_source_error_policy.dart';
import 'package:PiliMax/plugin/pl_player/preview_request_coordinator.dart';
import 'package:PiliMax/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliMax/services/live_pip_overlay_service.dart';
import 'package:PiliMax/services/pip_overlay_service.dart';
import 'package:PiliMax/services/service_locator.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/android/android_helper.dart';
import 'package:PiliMax/utils/android/bindings.g.dart';
import 'package:PiliMax/utils/asset_utils.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/extension/box_ext.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:PiliMax/utils/image_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:archive/archive.dart' show getCrc32;
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, DeviceOrientation;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:path/path.dart' as path;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

typedef PlayCallback = Future<void>? Function();

class PlPlayerController with BlockConfigMixin {
  Player? _videoPlayerController;
  VideoController? _videoController;

  static PlPlayerController? _instance;

  final playerStatus = PlPlayerStatus(.playing);

  final Rx<DataStatus> dataStatus = Rx(.none);

  Duration? seekToPos;
  bool hasToasted = false;
  final RxBool isSeeking = false.obs;

  final RxInt position = RxInt(0);

  int get positionInMilliseconds =>
      videoPlayerController?.state.position.inMilliseconds ?? 0;

  final RxInt buffered = RxInt(0);

  final RxInt duration = RxInt(0);

  int durationInMilliseconds = 0;

  void updateDuration(Duration value) {
    duration.value = value.inSeconds;
    durationInMilliseconds = value.inMilliseconds;
  }

  int _playerCount = 0;

  late double lastPlaybackSpeed = 1.0;
  final RxDouble _playbackSpeed = Pref.playSpeedDefault.obs;
  late final RxDouble _longPressSpeed = Pref.longPressSpeedDefault.obs;

  final RxDouble volume = RxDouble(
    PlatformUtils.isDesktop ? Pref.desktopVolume : 1.0,
  );
  final setSystemBrightness = Pref.setSystemBrightness;

  /// 系统音量（仅在应用内音量模式下用于追踪当前系统音量）
  final RxDouble systemVolume = RxDouble(1.0);

  /// duck 相关状态
  bool _isDucked = false;
  double _preDuckVolume = 1.0;

  /// 亮度控制条

  final RxDouble brightness = (-1.0).obs;

  final RxBool showControls = false.obs;

  final RxBool showBrightnessStatus = false.obs;

  final RxBool longPressStatus = false.obs;

  final RxBool controlsLock = false.obs;

  final RxBool isFullScreen = false.obs;

  void Function(bool isFullScreen)? onFullScreenChanged;
  // 系统原生 PiP 状态
  final RxBool isNativePip = false.obs;
  // 默认投稿视频格式

  bool isLive = false;

  bool _isVertical = false;

  final Rx<VideoFitType> videoFit = Rx(.contain);

  late final RxBool continuePlayInBackground =
      Pref.continuePlayInBackground.obs;

  bool _autoPlay = false;

  // 记录历史记录
  int? _aid;
  String? _bvid;
  int? cid;
  int? roomId;
  int? _epid;
  int? _seasonId;
  int? _pgcType;
  VideoType _videoType = VideoType.ugc;
  int _heartDuration = 0;
  int? width;
  int? height;

  late final tryLook = !Accounts.get(AccountType.video).isLogin && Pref.p1080;

  late DataSource dataSource;

  Timer? _timer;
  // Cancelled by the source coordinator and by [_cancelSubForSeek].
  // ignore: cancel_subscriptions
  StreamSubscription? _subForSeek;

  Box setting = GStorage.setting;

  String get bvid => _bvid!;

  bool get _hasPlaybackProgress =>
      position.value > 0 || buffered.value > 0 || positionInMilliseconds > 0;

  bool get _hasUsableBuffer => buffered.value > position.value;

  bool _shouldSilenceRecoverableError(String event) {
    if (!PlPlayerSourceErrorPolicy.isTransientNetworkError(event)) {
      return false;
    }
    return (playerStatus.isPlaying && _hasPlaybackProgress) ||
        (!isBuffering.value && _hasPlaybackProgress) ||
        (isBuffering.value && _hasUsableBuffer);
  }

  bool isCurrentVideoSource({
    required String bvid,
    required int cid,
    Object? sourceOwner,
  }) =>
      _activeSourceGeneration != null &&
      (sourceOwner == null || isSourceOwnerActive(sourceOwner)) &&
      dataStatus.value == DataStatus.loaded &&
      _bvid == bvid &&
      this.cid == cid;

  /// 视频播放速度
  double get playbackSpeed => _playbackSpeed.value;

  // 长按倍速
  double get longPressSpeed => _longPressSpeed.value;

  /// [videoPlayerController] instance of Player
  Player? get videoPlayerController => _videoPlayerController;

  /// [videoController] instance of Player
  VideoController? get videoController => _videoController;

  bool isMuted = false;

  /// 听视频
  late final RxBool onlyPlayAudio = false.obs;

  /// 镜像
  late final RxBool flipX = false.obs;

  late final RxBool flipY = false.obs;

  final RxBool isBuffering = true.obs;

  /// 全屏方向
  // ignore: unnecessary_getters_setters
  bool get isVertical => _isVertical;

  void updateVerticalState(bool isVertical) {
    _isVertical = isVertical;
  }

  set isVertical(bool value) {
    _isVertical = value;
  }

  /// 弹幕开关
  late final RxBool enableShowDanmaku = Pref.enableShowDanmaku.obs;
  late final RxBool enableShowLiveDanmaku = Pref.enableShowLiveDanmaku.obs;
  RxBool get enableShowDanmakuAdaptive =>
      isLive ? enableShowLiveDanmaku : enableShowDanmaku;

  late final bool autoPiP = Pref.autoPiP;
  bool get isPipMode =>
      isNativePip.value ||
      (Platform.isAndroid && AndroidHelper.isPipMode) ||
      (PlatformUtils.isDesktop && isDesktopPip);
  late bool isDesktopPip = false;
  late Rect _lastWindowBounds;

  late final showWindowTitleBar = Pref.showWindowTitleBar;
  late final RxBool isAlwaysOnTop = false.obs;
  Future<void> setAlwaysOnTop(bool value) {
    isAlwaysOnTop.value = value;
    return windowManager.setAlwaysOnTop(value);
  }

  Future<void> exitDesktopPip() {
    isDesktopPip = false;
    return Future.wait([
      if (showWindowTitleBar)
        windowManager.setTitleBarStyle(TitleBarStyle.normal),
      windowManager.setMinimumSize(const Size(400, 700)),
      windowManager.setBounds(_lastWindowBounds),
      setAlwaysOnTop(false),
      windowManager.setAspectRatio(0),
    ]);
  }

  Future<void> enterDesktopPip() async {
    if (isFullScreen.value) return;

    isDesktopPip = true;

    _lastWindowBounds = await windowManager.getBounds();

    if (showWindowTitleBar) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }

    final Size size;
    final state = videoPlayerController!.state;
    int width = state.width;
    int height = state.height;
    if (width == 0) {
      width = this.width ?? 16;
    }
    if (height == 0) {
      height = this.height ?? 9;
    }
    if (height > width) {
      size = Size(280.0, 280.0 * height / width);
    } else {
      size = Size(280.0 * width / height, 280.0);
    }

    await windowManager.setMinimumSize(size);
    setAlwaysOnTop(true);
    windowManager
      ..setSize(size)
      ..setAspectRatio(width / height);
  }

  void toggleDesktopPip() {
    if (isDesktopPip) {
      exitDesktopPip();
    } else {
      enterDesktopPip();
    }
  }

  late bool _isAutoEnterPip = false;
  bool get isAutoEnterPip => _isAutoEnterPip;

  static bool get _isCurrVideoPage {
    final routing = Get.routing;
    if (routing.route is! GetPageRoute) {
      return false;
    }
    return _isVideoPage(routing.current);
  }

  static bool _isVideoPage(String routeName) {
    return routeName == '/videoV' || routeName == '/liveRoom';
  }

  bool get _isInInAppPip {
    return PipOverlayService.isInPipMode || LivePipOverlayService.isInPipMode;
  }

  void enterPip({bool autoEnter = false}) {
    if (videoPlayerController != null) {
      final state = videoPlayerController!.state;
      PageUtils.enterPip(
        autoEnter: autoEnter,
        width: state.width == 0 ? width : state.width,
        height: state.height == 0 ? height : state.height,
        isLive: isLive,
        isPlaying: playerStatus.isPlaying,
      );
    }
  }

  // void _disableAutoEnterPipIfNeeded() {
  //   // 对齐上游逻辑，如果是从视频页返回到非视频页，则切断 Auto-Enter PiP
  //   if (!_isPreviousVideoPage) {
  //     _disableAutoEnterPip();
  //   }
  // }

  void disableAutoEnterPip() => _disableAutoEnterPip();

  void _disableAutoEnterPip() {
    if (_isAutoEnterPip) {
      PiliAndroidHelper.disableAutoEnterPip();
    }
  }

  // 弹幕相关配置
  late final enableTapDm = PlatformUtils.isMobile && Pref.enableTapDm;
  late RuleFilter filters = Pref.danmakuFilterRule;
  // 关联弹幕控制器
  DanmakuController<DanmakuExtra>? danmakuController;
  bool showDanmaku = true;
  Set<int> dmState = <int>{};
  late final mergeDanmaku = Pref.mergeDanmaku;
  late final String midHash = getCrc32(
    ascii.encode(Accounts.main.mid.toString()),
    0,
  ).toRadixString(16);
  late final RxDouble danmakuOpacity = Pref.danmakuOpacity.obs;

  late List<double> speedList = Pref.speedList;
  late bool enableAutoLongPressSpeed = Pref.enableAutoLongPressSpeed;
  late final showControlDuration = Pref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);
  // 字幕
  late double subtitleFontScale = Pref.subtitleFontScale;
  late double subtitleFontScaleFS = Pref.subtitleFontScaleFS;
  late int subtitlePaddingH = Pref.subtitlePaddingH;
  late int subtitlePaddingB = Pref.subtitlePaddingB;
  late double subtitleBgOpacity = Pref.subtitleBgOpacity;
  final bool showVipDanmaku = Pref.showVipDanmaku; // loop unswitching
  late double subtitleStrokeWidth = Pref.subtitleStrokeWidth;
  late int subtitleFontWeight = Pref.subtitleFontWeight;
  // Secondary subtitles share positioning with primary subtitles.
  late double subtitleSecondaryFontScale = Pref.subtitleSecondaryFontScale;
  late double subtitleSecondaryFontScaleFS = Pref.subtitleSecondaryFontScaleFS;
  late double subtitleSecondaryBgOpacity = Pref.subtitleSecondaryBgOpacity;
  late double subtitleSecondaryStrokeWidth = Pref.subtitleSecondaryStrokeWidth;
  late int subtitleSecondaryFontWeight = Pref.subtitleSecondaryFontWeight;
  late double subtitleSecondarySpacing = Pref.subtitleSecondarySpacing;

  // settings
  late final showFSActionItem = Pref.showFSActionItem;
  late final enableShrinkVideoSize = Pref.enableShrinkVideoSize;
  late final darkVideoPage = Pref.darkVideoPage;
  late final enableSlideVolumeBrightness = Pref.enableSlideVolumeBrightness;
  late final enableSlideFS = Pref.enableSlideFS;
  late final enableDragSubtitle = Pref.enableDragSubtitle;
  late final fastForBackwardDuration = Duration(
    seconds: Pref.fastForBackwardDuration,
  );

  late final horizontalSeasonPanel = Pref.horizontalSeasonPanel;
  late final preInitPlayer = Pref.preInitPlayer;
  late final showRelatedVideo = Pref.showRelatedVideo;
  late final showVideoReply = Pref.showVideoReply;
  late final showBangumiReply = Pref.showBangumiReply;
  late final reverseFromFirst = Pref.reverseFromFirst;
  late final horizontalPreview = Pref.horizontalPreview;
  DmChartSource get dmChartSource => Pref.dmChartSource;
  bool get showDmChart => dmChartSource.isEnabled;
  late final showViewPoints = Pref.showViewPoints;
  late final showFsScreenshotBtn = Pref.showFsScreenshotBtn;
  late final showFsLockBtn = Pref.showFsLockBtn;
  late final keyboardControl = Pref.keyboardControl;
  late final uiScale = Pref.uiScale;

  late final bool autoEnterFullScreen = Pref.autoEnterFullScreen;
  late final bool autoExitFullscreen = Pref.autoExitFullscreen;
  late final bool autoPlayEnable = Pref.autoPlayEnable;
  late final bool enableVerticalExpand = Pref.enableVerticalExpand;
  late final bool pipNoDanmaku = Pref.pipNoDanmaku;

  late final bool tempPlayerConf = Pref.tempPlayerConf;

  late int? cacheVideoQa = PlatformUtils.isMobile ? null : Pref.defaultVideoQa;
  late int cacheAudioQa = Pref.defaultAudioQa;
  bool enableHeart = true;
  late final String? hwdec = Pref.enableHA ? Pref.hardwareDecoding : null;

  late final progressType = Pref.btmProgressBehavior;
  late final enableQuickDouble = Pref.enableQuickDouble;
  late final fullScreenGestureReverse = Pref.fullScreenGestureReverse;

  late final isRelative = Pref.useRelativeSlide;
  late final offset = isRelative
      ? Pref.sliderDuration / 100
      : Pref.sliderDuration * 1000;

  num get sliderScale => isRelative ? durationInMilliseconds * offset : offset;

  // 播放顺序相关
  late PlayRepeat playRepeat = Pref.playRepeat;

  TextStyle _buildSubtitleStyle({
    required double fontScale,
    required double fontScaleFS,
    required int fontWeight,
    required double bgOpacity,
  }) => TextStyle(
    height: 1.5,
    fontSize: 16 * (isFullScreen.value ? fontScaleFS : fontScale),
    letterSpacing: 0.1,
    wordSpacing: 0.1,
    color: Colors.white,
    fontWeight: FontWeight.values[fontWeight],
    backgroundColor: bgOpacity == 0
        ? null
        : Colors.black.withValues(alpha: bgOpacity),
  );

  TextStyle get subTitleStyle => _buildSubtitleStyle(
    fontScale: subtitleFontScale,
    fontScaleFS: subtitleFontScaleFS,
    fontWeight: subtitleFontWeight,
    bgOpacity: subtitleBgOpacity,
  );

  TextStyle get subTitleSecondaryStyle => _buildSubtitleStyle(
    fontScale: subtitleSecondaryFontScale,
    fontScaleFS: subtitleSecondaryFontScaleFS,
    fontWeight: subtitleSecondaryFontWeight,
    bgOpacity: subtitleSecondaryBgOpacity,
  );

  late final Rx<SubtitleViewConfiguration> subtitleConfig = getSubConfig.obs;
  String? _activeVideoContextKey;

  SubtitleViewConfiguration get getSubConfig {
    final subTitleStyle = this.subTitleStyle;
    final secondaryStyle = subTitleSecondaryStyle;

    TextStyle? strokeOf(TextStyle base, double bgOpacity, double strokeWidth) =>
        bgOpacity == 0
        ? base.copyWith(
            color: null,
            background: null,
            backgroundColor: null,
            foreground: Paint()
              ..color = Colors.black
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth,
          )
        : null;

    return SubtitleViewConfiguration(
      style: subTitleStyle,
      strokeStyle: strokeOf(
        subTitleStyle,
        subtitleBgOpacity,
        subtitleStrokeWidth,
      ),
      secondaryStyle: secondaryStyle,
      secondaryStrokeStyle: strokeOf(
        secondaryStyle,
        subtitleSecondaryBgOpacity,
        subtitleSecondaryStrokeWidth,
      ),
      spacing: subtitleSecondarySpacing,
      padding: EdgeInsets.only(
        left: subtitlePaddingH.toDouble(),
        right: subtitlePaddingH.toDouble(),
        bottom: subtitlePaddingB.toDouble(),
      ),
      textScaleFactor: 1,
    );
  }

  void updateSubtitleStyle() {
    subtitleConfig.value = getSubConfig;
  }

  void onUpdatePadding(EdgeInsets padding) {
    subtitlePaddingB = padding.bottom.round().clamp(0, 200);
    putSubtitleSettings();
  }

  static PlPlayerController? get instance => _instance;

  static bool instanceExists() {
    return _instance != null;
  }

  static void setPlayCallBack(PlayCallback? playCallBack) {
    _playCallBack = playCallBack;
  }

  static PlayCallback? _playCallBack;

  static Future<void>? playIfExists() {
    if (_instance != null && !(_instance!.playerStatus.isPlaying)) {
      return _instance!.play();
    }

    return _playCallBack?.call();
  }

  // try to get PlayerStatus
  static PlayerStatus? getPlayerStatusIfExists() {
    return _instance?.playerStatus.value;
  }

  static Future<void> pauseIfExists({
    bool notify = true,
    bool isInterrupt = false,
  }) async {
    if (_instance?.playerStatus.isPlaying ?? false) {
      await _instance?.pause(notify: notify, isInterrupt: isInterrupt);
    }
  }

  static Future<void> seekToIfExists(
    Duration position, {
    bool isSeek = true,
  }) async {
    await _instance?.seekTo(position, isSeek: isSeek);
  }

  static double? getVolumeIfExists() {
    return _instance?.volume.value;
  }

  static Future<void>? setVolumeIfExists(
    double volumeNew, {
    bool showIndicator = true,
  }) {
    return _instance?.setVolume(volumeNew, showIndicator: showIndicator);
  }

  Box video = GStorage.video;

  bool visible = true;

  DeviceOrientation? _orientation;
  late final checkIsAutoRotate = Platform.isAndroid && mode != .gravity;
  StreamSubscription<OrientationParams>? _orientationListener;

  void _stopOrientationListener() {
    _orientationListener?.cancel();
    _orientationListener = null;
  }

  void _onOrientationChanged(OrientationParams param) {
    _orientation = param.orientation;
    if (Platform.isIOS && !visible) return;
    final orientation = param.orientation;
    final isFullScreen = this.isFullScreen.value;
    if (checkIsAutoRotate &&
        param.isAutoRotate != true &&
        (!isFullScreen ||
            _isVertical ||
            orientation == .portraitUp ||
            orientation == .portraitDown)) {
      return;
    }
    switch (orientation) {
      case .portraitUp:
        if (!_isVertical && controlsLock.value) return;
        if (!horizontalScreen && !_isVertical && isFullScreen) {
          if (!isManualFS) {
            triggerFullScreen(status: false, orientation: orientation);
          }
        } else {
          portraitUpMode();
        }
      case .portraitDown:
        if (!horizontalScreen) return;
        if (!_isVertical && controlsLock.value) return;
        portraitDownMode();
      case .landscapeLeft:
        if (!horizontalScreen && !isFullScreen) {
          triggerFullScreen(orientation: orientation, isManualFS: false);
        } else {
          landscapeLeftMode();
        }
      case .landscapeRight:
        if (!horizontalScreen && !isFullScreen) {
          triggerFullScreen(orientation: orientation, isManualFS: false);
        } else {
          landscapeRightMode();
        }
    }
  }

  // 添加一个私有构造函数
  PlPlayerController._() {
    _sourceCoordinator = PlPlayerSourceCoordinator<Player>(
      currentPlayer: () => _videoPlayerController,
      onSourceInvalidated: _handleSourceInvalidated,
    );
    if (PlatformUtils.isMobile) {
      _orientationListener = NativeDeviceOrientationPlatform.instance
          .onOrientationChanged(
            checkIsAutoRotate: checkIsAutoRotate,
            angleDegrees: Platform.isAndroid ? Pref.angleDegrees : null,
          )
          .listen(_onOrientationChanged);
    }

    if (!Accounts.heartbeat.isLogin || Pref.historyPause) {
      enableHeart = false;
    }

    if (Platform.isAndroid) {
      Utils.channel.setMethodCallHandler((call) async {
        if (call.method == 'onPipChanged') {
          final bool isInPip = call.arguments as bool;
          isNativePip.value = isInPip;
          PipOverlayService.isNativePip = isInPip;
          LivePipOverlayService.isNativePip = isInPip;
        }
      });

      if (autoPiP) {
        if (DeviceUtils.sdkInt < 31) {
          AndroidHelper$ToDart.onUserLeaveHint = Runnable.implement(
            $Runnable(run: _onUserLeaveHint),
          );
        } else {
          _isAutoEnterPip = true;
        }
      }
    }
  }

  void _onUserLeaveHint() {
    if (_isInInAppPip) {
      enterPip();
      return;
    }
    if (playerStatus.isPlaying && _isCurrVideoPage) {
      enterPip();
    }
  }

  // 获取实例 传参
  static PlPlayerController getInstance({bool isLive = false}) {
    // 如果实例尚未创建，则创建一个新实例
    return (_instance ??= PlPlayerController._())
      ..isLive = isLive
      .._playerCount += 1;
  }

  static PlPlayerController ensureInstance({bool isLive = false}) {
    return (_instance ??= PlPlayerController._())..isLive = isLive;
  }

  static bool _isAnimPgcType(int? pgcType) => pgcType == 1 || pgcType == 4;

  void resetTempSettings({
    int? nextPgcType,
    required int sourceGeneration,
  }) {
    if (!tempPlayerConf) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[PlPlayer] resetTempSettings (currentContext: $_activeVideoContextKey, nextPgcType: $nextPgcType)',
      );
    }

    enableShowDanmaku.value = Pref.enableShowDanmaku;
    enableShowLiveDanmaku.value = Pref.enableShowLiveDanmaku;
    videoPlayerServiceHandler?.enableBackgroundPlay = Pref.enableBackgroundPlay;
    continuePlayInBackground.value = Pref.continuePlayInBackground;
    playRepeat = Pref.playRepeat;
    cacheVideoQa = PlatformUtils.isMobile ? null : Pref.defaultVideoQa;
    cacheAudioQa = Pref.defaultAudioQa;
    if (_playbackSpeed.value != playSpeedDefault &&
        _sourceCoordinator.isCurrent(sourceGeneration)) {
      _publishPlaybackSpeed(
        speed: playSpeedDefault,
        previousSpeed: _playbackSpeed.value,
      );
    }

    final defaultSuperResolutionType = _isAnimPgcType(nextPgcType)
        ? Pref.superResolutionType
        : SuperResolutionType.disable;
    superResolutionType.value = defaultSuperResolutionType;
    if (_videoPlayerController != null) {
      unawaited(setShader(defaultSuperResolutionType, _videoPlayerController!));
    }
  }

  late final PlPlayerSourceCoordinator<Player> _sourceCoordinator;
  bool get processing => _sourceCoordinator.processing;

  int? get _activeSourceGeneration {
    final generation = _sourceCoordinator.activeGeneration;
    return generation != null && _sourceCoordinator.isActive(generation)
        ? generation
        : null;
  }

  bool isSourceOwnerActive(Object sourceOwner) =>
      _sourceCoordinator.isOwnerActive(sourceOwner);

  bool _isPlayerOperationCurrent(
    int generation,
    Player player, {
    bool requireActive = false,
  }) => _sourceCoordinator.isPlayerCurrent(
    generation,
    player,
    requireActive: requireActive,
  );

  // offline
  bool get isFileSource => dataSource is FileSource;

  late final _audioNormalization = Pref.audioNormalization;
  late final enableAudioNormalization =
      Platform.isAndroid && _audioNormalization != '0';
  late final String _audioNormalizationParam =
      AudioNormalization.getParamFromConfig(_audioNormalization);

  // 初始化资源
  Future<bool> setDataSource(
    DataSource dataSource, {
    required Object sourceOwner,
    bool isLive = false,
    bool autoplay = true,
    // 初始化播放位置
    Duration? seekTo,
    // 初始化播放速度
    double speed = 1.0,
    int? width,
    int? height,
    Duration? duration,
    // 方向
    bool? isVertical,
    // 记录历史记录
    int? aid,
    String? bvid,
    int? cid,
    int? roomId,
    int? epid,
    int? seasonId,
    int? pgcType,
    VideoType? videoType,
    VoidCallback? onInit,
    Volume? volume,
    bool autoFullScreenFlag = false,
  }) {
    return _sourceCoordinator.openSource(
      owner: sourceOwner,
      prepare: (attempt) => _prepareSource(
        attempt: attempt,
        dataSource: dataSource,
        isLive: isLive,
        autoplay: autoplay,
        seekTo: seekTo,
        speed: speed,
        width: width,
        height: height,
        duration: duration,
        isVertical: isVertical,
        aid: aid,
        bvid: bvid,
        cid: cid,
        roomId: roomId,
        epid: epid,
        seasonId: seasonId,
        pgcType: pgcType,
        videoType: videoType,
        onInit: onInit,
        volume: volume,
        autoFullScreenFlag: autoFullScreenFlag,
        sourceOwner: sourceOwner,
      ),
      onError: (err, stackTrace, attempt) {
        if (attempt.isCurrent) {
          dataStatus.value = DataStatus.error;
        }
        if (kDebugMode) {
          debugPrint(stackTrace.toString());
          debugPrint(
            'PlPlayer source setup failed (${err.runtimeType})',
          );
        }
      },
    );
  }

  Future<PlPlayerPreparedSource<Player>?> _prepareSource({
    required PlPlayerSourceAttempt<Player> attempt,
    required DataSource dataSource,
    required bool isLive,
    required bool autoplay,
    required Duration? seekTo,
    required double speed,
    required int? width,
    required int? height,
    required Duration? duration,
    required bool? isVertical,
    required int? aid,
    required String? bvid,
    required int? cid,
    required int? roomId,
    required int? epid,
    required int? seasonId,
    required int? pgcType,
    required VideoType? videoType,
    required VoidCallback? onInit,
    required Volume? volume,
    required bool autoFullScreenFlag,
    required Object sourceOwner,
  }) async {
    bool isCurrent() => attempt.isCurrent;
    attempt.registerAbort(_abortUncommittedSourcePlayer);
    if (!isCurrent()) return null;
    final nextVideoContextKey = PipOverlayService.buildVideoContextKey(
      videoType: videoType ?? VideoType.ugc,
      bvid: bvid,
      cid: cid,
      epId: epid,
      seasonId: seasonId,
    );
    final shouldResetTempSettings =
        tempPlayerConf &&
        _activeVideoContextKey != null &&
        nextVideoContextKey != null &&
        nextVideoContextKey != _activeVideoContextKey;
    if (shouldResetTempSettings) {
      resetTempSettings(
        nextPgcType: pgcType,
        sourceGeneration: attempt.generation,
      );
      if (!isCurrent()) return null;
    }
    _activeVideoContextKey = nextVideoContextKey;
    this.isLive = isLive;
    _videoType = videoType ?? VideoType.ugc;
    this.width = width;
    this.height = height;
    this.dataSource = dataSource;
    _autoPlay = autoplay;
    // 初始化视频倍速
    // _playbackSpeed.value = speed;
    // 初始化数据加载状态
    dataStatus.value = DataStatus.loading;
    // 初始化全屏方向
    _isVertical = isVertical ?? false;
    _aid = aid;
    _bvid = bvid;
    this.cid = cid;
    this.roomId = roomId;
    _epid = epid;
    _seasonId = seasonId;
    _pgcType = pgcType;

    if (showSeekPreview) {
      _clearPreview();
    }
    if (_videoPlayerController != null &&
        _videoPlayerController!.state.playing) {
      await _pauseForSourceSwitch(attempt);
      if (!isCurrent()) return null;
    }

    if (_playerCount == 0 || !isCurrent()) return null;
    // 配置Player 音轨、字幕等等
    final preparedMedia = await _prepareVideoSource(
      dataSource,
      seekTo,
      volume,
      attempt: attempt,
    );
    if (preparedMedia == null) return null;
    final (:player, :media, :primarySource) = preparedMedia;

    if (_playerCount == 0 || !isCurrent()) {
      if (_playerCount == 0 && identical(_videoPlayerController, player)) {
        _videoPlayerController = null;
        _videoController = null;
        await player.dispose();
      }
      return null;
    }

    final sourceErrorContext = PlPlayerSourceErrorContext(
      primarySource: primarySource,
      isFileSource: dataSource is FileSource,
      isLive: isLive,
      onlyPlayAudio: onlyPlayAudio.value,
    );
    final openingErrors = PlPlayerOpeningErrorAccumulator();

    void captureOpeningError(String event) {
      openingErrors.add(
        PlPlayerSourceErrorPolicy.classify(
          event: event,
          context: sourceErrorContext,
          phase: PlPlayerSourceErrorPhase.opening,
        ),
        event,
      );
    }

    void ensureOpeningSucceeded() {
      if (openingErrors.hasFatalPrimaryError) {
        throw StateError('Player reported an error while opening source');
      }
    }

    return PlPlayerPreparedSource<Player>(
      player: player,
      subscribe: (lease) => _createSourceListeners(
        player,
        lease,
        sourceErrorContext: sourceErrorContext,
        sourceDataSource: dataSource,
        onOpeningError: captureOpeningError,
      ),
      open: (_) async {
        await player.open(media, play: false);
        // media-kit reports some native open failures only through its
        // asynchronous error stream instead of completing open with an
        // error. Give queued error delivery a turn before committing.
        await Future<void>.delayed(Duration.zero);
        ensureOpeningSucceeded();
      },
      didOpen: (lease) {
        // Close the synchronous handoff between the open-stage check and the
        // coordinator's active-source commit.
        ensureOpeningSucceeded();
        _syncPlayerStateAfterOpen(lease);
        updateDuration(duration ?? player.state.duration);
        position.value = buffered.value = seekTo?.inSeconds ?? 0;
        for (final error in openingErrors.deferredErrors) {
          if (!lease.isCurrent(
            _videoPlayerController,
            requireActive: true,
          )) {
            return;
          }
          final keepSource = _handleSourceError(
            error.event,
            lease,
            sourceErrorContext,
            dataSource,
            disposition: error.action,
            fromOpening: true,
          );
          if (!keepSource) {
            _sourceCoordinator.invalidate();
            return;
          }
        }
        if (!lease.isCurrent(
          _videoPlayerController,
          requireActive: true,
        )) {
          return;
        }
        dataStatus.value = .loaded;
        if (autoFullScreenFlag && autoEnterFullScreen) {
          triggerFullScreen(status: true);
        }
      },
      initialize: (lease) async {
        await _initializePlayer(lease);
        if (lease.isCurrent(_videoPlayerController, requireActive: true) &&
            isSourceOwnerActive(sourceOwner)) {
          onInit?.call();
        }
      },
      discard: attempt.abort,
    );
  }

  Future<void> _abortUncommittedSourcePlayer() async {
    final player = _videoPlayerController;
    _videoPlayerController = null;
    _videoController = null;
    if (player != null) {
      await player.dispose();
    }
  }

  void _handleSourceInvalidated() {
    unawaited(WakelockPlus.disable());
    _sourceCoordinator.releaseSourceTimer(_timer, cancel: true);
    _timer = null;
    volumeTimer?.cancel();
    volumeTimer = null;
    volumeIndicator.value = false;
    volumeInterceptEventStream = false;
    cancelLongPressTimer();
    _cancelSubForSeek();
    _dismissSourceScopedScreenshot();
  }

  Future<void> _pauseForSourceSwitch(
    PlPlayerSourceAttempt<Player> attempt,
  ) async {
    final player = _videoPlayerController;
    if (player == null || !player.state.playing) return;
    final lease = attempt.bind(player);

    await player.pause();
    unawaited(WakelockPlus.disable());
    unawaited(audioSessionHandler?.setActive(false));
    if (!lease.isCurrent(_videoPlayerController)) return;

    playerStatus.value = PlayerStatus.paused;
    videoPlayerServiceHandler?.onStatusChange(
      playerStatus.value,
      isBuffering.value,
      isLive,
    );
  }

  String? shadersDirPath;
  Future<String> get copyShadersToExternalDirectory async {
    if (shadersDirPath != null) {
      return shadersDirPath!;
    }

    return shadersDirPath = await AssetUtils.getOrCopy(
      'assets/shaders',
      Assets.mpvAnime4KShaders.followedBy(Assets.mpvAnime4KShadersLite),
      path.join(appSupportDirPath, 'anime_shaders'),
    );
  }

  late final isAnim = _pgcType == 1 || _pgcType == 4;
  late final Rx<SuperResolutionType> superResolutionType =
      (isAnim ? Pref.superResolutionType : SuperResolutionType.disable).obs;
  Future<void> setShader([SuperResolutionType? type, NativePlayer? pp]) async {
    if (type == null) {
      type = superResolutionType.value;
    } else {
      superResolutionType.value = type;
      if (isAnim && !tempPlayerConf) {
        setting.put(SettingBoxKey.superResolutionType, type.index);
      }
    }
    pp ??= _videoPlayerController!;
    switch (type) {
      case SuperResolutionType.disable:
        return pp.command(const ['change-list', 'glsl-shaders', 'clr', '']);
      case SuperResolutionType.efficiency:
        return pp.command([
          'change-list',
          'glsl-shaders',
          'set',
          PathUtils.buildShadersAbsolutePath(
            await copyShadersToExternalDirectory,
            Assets.mpvAnime4KShadersLite,
          ),
        ]);
      case SuperResolutionType.quality:
        return pp.command([
          'change-list',
          'glsl-shaders',
          'set',
          PathUtils.buildShadersAbsolutePath(
            await copyShadersToExternalDirectory,
            Assets.mpvAnime4KShaders,
          ),
        ]);
    }
  }

  static final loudnormRegExp = RegExp('loudnorm=([^,]+)');

  Future<(Player, VideoController)> _initPlayer() async {
    assert(_videoPlayerController == null);
    if (PlatformUtils.isMobile && Pref.enableAppVolume) {
      // 移动平台应用内音量模式：初始化系统音量
      systemVolume.value = (await FlutterVolumeController.getVolume()) ?? 1.0;
      // 从持久化存储读取应用内音量
      volume.value = Pref.appVolume;
    }
    final opt = {
      'video-sync': Pref.videoSync,
      if (Platform.isAndroid) 'ao': Pref.audioOutput,
      'volume':
          (PlatformUtils.isMobile
                  ? (Pref.enableAppVolume
                        ? volume.value * 100
                        : Pref.playerVolume)
                  : volume.value * 100)
              .toString(),
      'volume-max': kMaxVolume.toString(),
    };
    final autosync = Pref.autosync;
    if (autosync != '0') {
      opt['autosync'] = autosync;
    }

    final player = await Player.create(
      configuration: PlayerConfiguration(
        logLevel: kDebugMode ? .warn : .error,
        options: opt,
      ),
    );

    assert(_videoController == null);

    try {
      final videoController = await VideoController.create(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: hwdec != null,
          androidAttachSurfaceAfterVideoParameters: false,
          hwdec: hwdec,
        ),
      );

      player.setMediaHeader(
        userAgent: BrowserUa.pc,
        referer: HttpString.baseUrl,
      );
      return (player, videoController);
    } catch (error, stackTrace) {
      try {
        await player.dispose();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Map<String, String>? _buffer;
  Map<String, String> get buffer =>
      _buffer ??= Pref.initBuffer(_playbackSpeed.value);
  Map<String, String>? _liveBuffer;
  Map<String, String> get liveBuffer => _liveBuffer ??= Pref.initLiveBuffer();

  // 配置播放器
  Future<({Player player, Media media, String primarySource})?>
  _prepareVideoSource(
    DataSource dataSource,
    Duration? seekTo,
    Volume? volume, {
    required PlPlayerSourceAttempt<Player> attempt,
  }) async {
    bool isCurrent() => attempt.isCurrent;
    if (!isCurrent()) return null;
    isBuffering.value = false;
    _heartDuration = 0;

    danmakuController?.clear();

    var player = _videoPlayerController;

    if (player == null) {
      final created = await _initPlayer();
      player = created.$1;
      if (_playerCount == 0 || !isCurrent()) {
        await player.dispose();
        return null;
      }
      _videoController = created.$2;
      _videoPlayerController = player;
      if (isAnim && superResolutionType.value != .disable) {
        await setShader();
        if (!isCurrent()) return null;
      }
    }

    final Map<String, String> extras = {};

    if (dataSource is FileSource) {
      extras['cache'] = 'no';
    } else {
      if (isLive) {
        extras.addAll(liveBuffer);
      } else {
        extras.addAll(buffer);
      }
    }

    var primarySource = dataSource.videoSource;
    String video = primarySource;
    if (dataSource.audioSource case final audio? when (audio.isNotEmpty)) {
      if (onlyPlayAudio.value) {
        video = audio;
        primarySource = audio;
      } else {
        // EDL length fields are UTF-8 byte counts, not Dart string lengths.
        video =
            ('edl://'
            '!no_clip;!no_chapters;'
            // '!delay_open,media_type=video;'
            '%${utf8.encode(video).length}%$video;'
            '!new_stream;!no_clip;!no_chapters;'
            // '!delay_open,media_type=audio;'
            '%${utf8.encode(audio).length}%$audio');
      }
      if (enableAudioNormalization) {
        final String audioNormalization;
        if (volume != null && volume.isNotEmpty) {
          audioNormalization = _audioNormalizationParam.replaceFirstMapped(
            loudnormRegExp,
            (i) =>
                'loudnorm=${volume.format(Map.fromEntries(i.group(1)!.split(':').map((item) {
                  final parts = item.split('=');
                  return MapEntry(parts[0].toLowerCase(), num.parse(parts[1]));
                })))}',
          );
        } else {
          audioNormalization = _audioNormalizationParam.replaceFirst(
            loudnormRegExp,
            AudioNormalization.getParamFromConfig(Pref.fallbackNormalization),
          );
        }
        if (audioNormalization.isNotEmpty) {
          extras['lavfi-complex'] = '"[aid1] $audioNormalization [ao]"';
        }
      }
    }

    if (!isCurrent()) return null;
    return (
      player: player,
      // Classify failures against the source that Media opens as primary.
      // Combined EDL keeps video primary; audio-only uses the audio source.
      primarySource: primarySource,
      media: Media(
        video,
        start: seekTo,
        extras: extras.isEmpty ? null : extras,
      ),
    );
  }

  void _syncPlayerStateAfterOpen(PlPlayerSourceLease<Player> lease) {
    final player = lease.player;
    if (!lease.isCurrent(_videoPlayerController, requireActive: true)) {
      return;
    }
    final state = player.state;
    position.value = state.position.inSeconds;
    updateDuration(state.duration);
    playerStatus.value = state.completed
        ? PlayerStatus.completed
        : state.playing
        ? PlayerStatus.playing
        : PlayerStatus.paused;
    unawaited(WakelockPlus.toggle(enable: state.playing));
    videoPlayerServiceHandler?.onStatusChange(
      playerStatus.value,
      isBuffering.value,
      isLive,
    );
  }

  Future<bool> refreshPlayer({int? generation}) {
    if (dataSource is FileSource) {
      return Future<bool>.value(false);
    }
    return _sourceCoordinator.refresh(
      generation: generation,
      open: (lease) async {
        final ctr = lease.player;
        if (ctr.current.isEmpty) return false;
        final media = ctr.current.last.copyWith(start: ctr.state.position);
        await ctr.open(media, play: true);
        return true;
      },
      didOpen: _syncPlayerStateAfterOpen,
    );
  }

  // 开始播放
  Future<void> _initializePlayer(
    PlPlayerSourceLease<Player> sourceLease,
  ) async {
    final player = sourceLease.player;
    bool isCurrent() =>
        _instance != null &&
        sourceLease.isCurrent(_videoPlayerController, requireActive: true);
    if (!isCurrent()) return;
    // 设置倍速
    if (isLive) {
      await _setPlaybackSpeedForSource(1.0, sourceLease);
      if (!isCurrent()) return;
    } else {
      if (player.state.rate != _playbackSpeed.value) {
        await _setPlaybackSpeedForSource(_playbackSpeed.value, sourceLease);
        if (!isCurrent()) return;
      }
    }
    _initVideoFit();
    await applyOnlyPlayAudioTrack();
    if (!isCurrent()) return;
    // 自动播放
    if (_autoPlay) {
      playIfExists();
    }
  }

  final Set<ValueChanged<Duration>> _positionListeners = {};
  final Set<ValueChanged<Duration>> _seekListeners = {};
  final Set<ValueChanged<PlayerStatus>> _statusListeners = {};

  /// 播放事件监听
  Iterable<StreamSubscription<dynamic>> _createSourceListeners(
    Player player,
    PlPlayerSourceLease<Player> sourceLease, {
    required PlPlayerSourceErrorContext sourceErrorContext,
    required DataSource sourceDataSource,
    void Function(String event)? onOpeningError,
  }) {
    final stream = player.stream;
    bool isCurrent() => sourceLease.isCurrent(
      _videoPlayerController,
      requireActive: true,
    );
    return [
      /// playing
      stream.playing.listen((bool playing) {
        if (!isCurrent()) return;
        WakelockPlus.toggle(enable: playing);
        if (playing) {
          if (_isAutoEnterPip) {
            if (_isCurrVideoPage || _isInInAppPip) {
              enterPip(autoEnter: true);
            } else {
              _disableAutoEnterPip();
            }
          }
          playerStatus.value = .playing;
        } else {
          _disableAutoEnterPip();
          playerStatus.value = .paused;
        }

        videoPlayerServiceHandler?.onStatusChange(
          playerStatus.value,
          isBuffering.value,
          isLive,
        );

        for (final element in _statusListeners) {
          element(playing ? .playing : .paused);
        }

        final seconds = player.state.position.inSeconds;
        if (seconds != 0) {
          makeHeartBeat(seconds, type: .status);
        }
      }),

      ///completed
      stream.completed.listen((bool completed) {
        if (!isCurrent()) return;
        if (completed) {
          playerStatus.value = .completed;

          for (final element in _statusListeners) {
            element(.completed);
          }

          makeHeartBeat(-1, type: .completed);
        }
      }),

      /// position
      stream.position.listen((Duration position) {
        if (!isCurrent()) return;
        final posInSeconds = position.inSeconds;

        if (posInSeconds != this.position.value) {
          if (!isSeeking.value) {
            this.position.value = posInSeconds;
          }

          videoPlayerServiceHandler?.onPositionChange(position);

          makeHeartBeat(posInSeconds);
        }

        for (final element in _positionListeners) {
          element(position);
        }
      }),
      stream.duration.listen((duration) {
        if (!isCurrent()) return;
        updateDuration(duration);
      }),
      stream.buffer.listen((Duration buffer) {
        if (!isCurrent()) return;
        buffered.value = buffer.inSeconds;
      }),
      stream.buffering.listen((bool buffering) {
        if (!isCurrent()) return;
        isBuffering.value = buffering;
        videoPlayerServiceHandler?.onStatusChange(
          playerStatus.value,
          buffering,
          isLive,
        );
      }),
      if (kDebugMode)
        stream.log.listen(((PlayerLog log) {
          if (!isCurrent()) return;
          final safePrefix = PlPlayerSourceErrorPolicy.sanitize(log.prefix);
          final safeText = PlPlayerSourceErrorPolicy.sanitize(log.text);
          if (log.level == 'error' || log.level == 'fatal') {
            Utils.reportError('${log.level}: $safePrefix: $safeText', null);
          } else {
            debugPrint('${log.level}: $safePrefix: $safeText');
          }
        })),
      stream.error.listen((String event) {
        if (!sourceLease.isCurrent(_videoPlayerController)) return;
        if (!isCurrent()) {
          onOpeningError?.call(event);
          return;
        }
        _handleSourceError(
          event,
          sourceLease,
          sourceErrorContext,
          sourceDataSource,
        );
      }),
    ];
  }

  bool _handleSourceError(
    String event,
    PlPlayerSourceLease<Player> sourceLease,
    PlPlayerSourceErrorContext sourceErrorContext,
    DataSource sourceDataSource, {
    PlPlayerSourceErrorAction? disposition,
    bool fromOpening = false,
  }) {
    final resolvedDisposition =
        disposition ??
        PlPlayerSourceErrorPolicy.classify(
          event: event,
          context: sourceErrorContext,
          phase: PlPlayerSourceErrorPhase.active,
          silenceRecoverable: _shouldSilenceRecoverableError(event),
          hasPlaybackProgress: _hasPlaybackProgress,
        );
    final safeEvent = PlPlayerSourceErrorPolicy.sanitize(event);
    switch (resolvedDisposition) {
      case PlPlayerSourceErrorAction.ignore:
        return true;
      case PlPlayerSourceErrorAction.fatalOpen:
        Utils.reportError(safeEvent);
        return false;
      case PlPlayerSourceErrorAction.retryLive:
        _sourceCoordinator.scheduleRetry(
          sourceLease,
          const Duration(seconds: 3),
          (lease) async {
            await _refreshSourceForRetry(
              lease,
              fromOpening: fromOpening,
            );
          },
          onError: _reportSourceOperationError,
        );
        return true;
      case PlPlayerSourceErrorAction.retryVod:
        _sourceCoordinator.scheduleRetry(
          sourceLease,
          const Duration(seconds: 3),
          (lease) async {
            if (lease.isCurrent(
                  _videoPlayerController,
                  requireActive: true,
                ) &&
                PlPlayerSourceErrorPolicy.shouldRunVodRetry(
                  phase: fromOpening
                      ? PlPlayerSourceErrorPhase.opening
                      : PlPlayerSourceErrorPhase.active,
                  isBuffering: isBuffering.value,
                  bufferedSeconds: buffered.value,
                )) {
              SmartDialog.showToast(
                '视频链接打开失败，重试中',
                displayTime: const Duration(milliseconds: 500),
              );
              await _refreshSourceForRetry(
                lease,
                fromOpening: fromOpening,
              );
            }
          },
          onError: _reportSourceOperationError,
        );
        return true;
      case PlPlayerSourceErrorAction.codecFallback:
        if (Platform.isAndroid) {
          try {
            if (sourceDataSource.onCodecOpenError?.call(safeEvent) == true) {
              return false;
            }
          } catch (err, stackTrace) {
            if (kDebugMode) {
              debugPrint(stackTrace.toString());
              debugPrint(
                'Codec open error handler failed (${err.runtimeType})',
              );
            }
          }
        }
        SmartDialog.showToast(
          '无法加载解码器, $safeEvent，可能会切换至软解',
        );
        return true;
      case PlPlayerSourceErrorAction.report:
        Utils.reportError(safeEvent);
        return true;
    }
  }

  Future<void> _refreshSourceForRetry(
    PlPlayerSourceLease<Player> lease, {
    required bool fromOpening,
  }) async {
    var refreshed = false;
    try {
      refreshed = await refreshPlayer(generation: lease.generation);
    } finally {
      if (fromOpening && !refreshed) {
        await _failOpeningRetry(lease);
      }
    }
  }

  Future<void> _failOpeningRetry(
    PlPlayerSourceLease<Player> lease,
  ) async {
    if (!lease.isCurrent(
      _videoPlayerController,
      requireActive: true,
    )) {
      return;
    }
    final player = lease.player;
    if (!identical(_videoPlayerController, player)) return;
    _videoPlayerController = null;
    _videoController = null;
    final failedGeneration = lease.generation + 1;
    _sourceCoordinator.invalidate();
    if (_sourceCoordinator.currentGeneration == failedGeneration &&
        _videoPlayerController == null) {
      dataStatus.value = DataStatus.error;
    }
    try {
      await player.dispose().timeout(_sourceCoordinator.timeouts.abort);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
        debugPrint(
          'PlPlayer opening retry cleanup failed (${error.runtimeType})',
        );
      }
    }
  }

  void _reportSourceOperationError(Object error, StackTrace stackTrace) {
    Utils.reportError(
      PlPlayerSourceErrorPolicy.sanitize(error.toString()),
      stackTrace,
    );
  }

  /// 移除事件监听
  void _cancelSubForSeek() {
    if (_subForSeek != null) {
      _sourceCoordinator.releaseSourceSubscription(
        _subForSeek,
        cancel: true,
      );
      _subForSeek = null;
    }
  }

  /// 跳转至指定位置
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    final generation = _activeSourceGeneration;
    final player = _videoPlayerController;
    if (_playerCount == 0 || generation == null || player == null) {
      return;
    }
    bool isCurrent() => _isPlayerOperationCurrent(
      generation,
      player,
      requireActive: true,
    );
    if (position < Duration.zero) {
      position = Duration.zero;
    }
    for (final listener in _seekListeners) {
      listener(position);
    }
    _heartDuration = position.inSeconds;

    Future<void> seek() async {
      try {
        if (isSeek) {
          /// 拖动进度条调节时，不等待第一帧，防止抖动
          await player.stream.buffer.first;
        }
        if (!isCurrent()) return;
        danmakuController?.clear();
        await player.seek(position);
      } catch (e) {
        if (kDebugMode) debugPrint('seek failed: $e');
      }
    }

    if (duration.value != 0) {
      await seek();
    } else {
      // if (kDebugMode) debugPrint('seek duration else');
      _cancelSubForSeek();
      _subForSeek = _sourceCoordinator.trackSourceSubscription(
        duration.listen((_) {
          if (isCurrent()) {
            unawaited(seek());
          }
          _cancelSubForSeek();
        }),
      );
    }
  }

  /// 设置倍速
  Future<void> setPlaybackSpeed(double speed) async {
    final generation = _activeSourceGeneration;
    final player = _videoPlayerController;
    if (generation == null || player == null) return;
    await _sourceCoordinator.runActive(
      generation: generation,
      operation: (lease) => _setPlaybackSpeedForSource(speed, lease),
    );
  }

  Future<bool> _setPlaybackSpeedForSource(
    double speed,
    PlPlayerSourceLease<Player> sourceLease,
  ) async {
    final player = sourceLease.player;
    bool isCurrent() => sourceLease.isCurrent(
      _videoPlayerController,
      requireActive: true,
    );
    if (!isCurrent()) return false;
    if (speed == player.state.rate) return true;

    final previousSpeed = _playbackSpeed.value;
    await player.setRate(speed);
    if (!isCurrent()) return false;

    _publishPlaybackSpeed(speed: speed, previousSpeed: previousSpeed);
    return true;
  }

  void _publishPlaybackSpeed({
    required double speed,
    required double previousSpeed,
  }) {
    lastPlaybackSpeed = previousSpeed;
    _playbackSpeed.value = speed;
    if (danmakuController != null) {
      try {
        DanmakuOption currentOption = danmakuController!.option;
        double defaultDuration = currentOption.duration * previousSpeed;
        double defaultStaticDuration =
            currentOption.staticDuration * previousSpeed;
        DanmakuOption updatedOption = currentOption.copyWith(
          duration: defaultDuration / speed,
          staticDuration: defaultStaticDuration / speed,
        );
        danmakuController!.updateOption(updatedOption);
      } catch (_) {}
    }
  }

  // 还原默认速度
  double playSpeedDefault = Pref.playSpeedDefault;
  Future<void> setDefaultSpeed() async {
    await setPlaybackSpeed(playSpeedDefault);
  }

  bool _showControlsOnNextPlay = false;

  void markManualEpisodeChange() {
    if (Pref.showControlsOnManualEpisodeChange) {
      _showControlsOnNextPlay = true;
    }
  }

  bool _consumeShowControlsOnNextPlay() {
    final showControls = _showControlsOnNextPlay;
    _showControlsOnNextPlay = false;
    return showControls;
  }

  /// 播放视频
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    final generation = _activeSourceGeneration;
    final player = _videoPlayerController;
    if (_playerCount == 0 || generation == null || player == null) return;
    bool isCurrent() => _isPlayerOperationCurrent(
      generation,
      player,
      requireActive: true,
    );
    // 播放时自动隐藏控制条
    final showControlsOnNextPlay = _consumeShowControlsOnNextPlay();
    // repeat为true，将从头播放
    if (repeat) {
      await seekTo(Duration.zero, isSeek: false);
      if (!isCurrent()) return;
    }

    await player.play();
    if (!isCurrent()) return;

    controls = !hideControls || showControlsOnNextPlay;
    audioSessionHandler?.setActive(true);

    playerStatus.value = PlayerStatus.playing;
    // screenManager.setOverlays(false);
  }

  /// 暂停播放
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    final player = _videoPlayerController;
    if (player == null) return;
    final lease = _sourceCoordinator.currentLease(player);
    if (lease == null) return;

    await player.pause();
    unawaited(WakelockPlus.disable());
    if (!lease.isCurrent(_videoPlayerController)) return;
    playerStatus.value = PlayerStatus.paused;

    // 主动暂停时让出音频焦点
    if (!isInterrupt) {
      audioSessionHandler?.setActive(false);
    }
  }

  bool tripling = false;

  /// 隐藏控制条
  void hideTaskControls() {
    _sourceCoordinator.releaseSourceTimer(_timer, cancel: true);
    late final Timer timer;
    timer = Timer(showControlDuration, () {
      if (!isSeeking.value && !tripling) {
        controls = false;
      }
      _sourceCoordinator.releaseSourceTimer(timer);
      if (identical(_timer, timer)) {
        _timer = null;
      }
    });
    _timer = _sourceCoordinator.trackSourceTimer(timer);
  }

  void onSeekEnd() {
    if (seekToPos != null) {
      feedBack();
    }
    if (showSeekPreview) {
      showPreview.value = false;
    }
    hasToasted = false;
    isSeeking.value = false;
    hideTaskControls();
  }

  final RxBool volumeIndicator = false.obs;
  Timer? _volumeTimer;
  Timer? get volumeTimer => _volumeTimer;
  set volumeTimer(Timer? value) {
    _sourceCoordinator.releaseSourceTimer(_volumeTimer);
    _volumeTimer = value;
    if (value != null) {
      _sourceCoordinator.trackSourceTimer(value);
    }
  }

  bool volumeInterceptEventStream = false;

  double get maxVolume => PlatformUtils.isDesktop
      ? Pref.maxVolume
      : (Pref.enableAppVolume && Pref.enableVolumeBoost ? 2.0 : 1.0);

  // 音量增强二次确认：是否已解锁突破 100%（松手后重置）
  bool volumeBoostUnlocked = false;

  // 手势滑动时的音量上限：未解锁时最大 1.0，解锁后最大 2.0
  double get gestureVolumeMax {
    if (Pref.enableAppVolume && Pref.enableVolumeBoost) {
      return volumeBoostUnlocked ? 2.0 : 1.0;
    }
    return maxVolume;
  }

  // 松手时重置解锁状态
  void onVolumeGestureEnd() {
    if (Pref.enableAppVolume && Pref.enableVolumeBoost) {
      volumeBoostUnlocked = false;
    }
  }

  Future<void> setVolume(double volume, {bool showIndicator = true}) async {
    if (this.volume.value != volume) {
      this.volume.value = volume;
      try {
        if (PlatformUtils.isDesktop) {
          await _videoPlayerController!.setVolume(volume * 100);
        } else {
          // 移动平台：根据设置选择音量控制方式
          if (Pref.enableAppVolume) {
            // 应用内音量模式：使用 media_kit 控制应用内音量
            _videoPlayerController?.setVolume(volume * 100);
          } else {
            // 默认模式：控制系统音量
            FlutterVolumeController.updateShowSystemUI(false);
            await FlutterVolumeController.setVolume(volume);
          }
        }
      } catch (err) {
        if (kDebugMode) debugPrint(err.toString());
      }
    }
    if (showIndicator) {
      volumeIndicator.value = true;
    }
    volumeInterceptEventStream = true;
    volumeTimer?.cancel();
    volumeTimer = Timer(const Duration(milliseconds: 200), () {
      volumeIndicator.value = false;
      volumeInterceptEventStream = false;
      if (PlatformUtils.isDesktop) {
        setting.put(SettingBoxKey.desktopVolume, volume.toPrecision(3));
      } else if (Pref.enableAppVolume) {
        // 移动平台应用内音量模式：保存音量到持久化存储
        // duck 期间不保存，避免保存临时的减半音量
        if (!_isDucked) {
          Pref.appVolume = volume;
        }
      }
    });
  }

  /// 处理应用内音量设置变更
  Future<void> onAppVolumeSettingChanged() async {
    if (!PlatformUtils.isMobile) return;

    // 如果播放器未初始化，直接返回（设置已保存，下次播放器初始化时生效）
    if (_videoPlayerController == null) return;

    if (Pref.enableAppVolume) {
      // 切换到应用内音量模式
      // 获取当前系统音量
      final currentSystemVolume =
          (await FlutterVolumeController.getVolume()) ?? 1.0;
      systemVolume.value = currentSystemVolume;

      final appVolume = (Pref.playerVolume / 100)
          .clamp(0.0, maxVolume)
          .toDouble();
      volume.value = appVolume;
      Pref.appVolume = appVolume;
      volumeBoostUnlocked = false;

      // 关闭上游固定增益，避免和应用内音量叠加
      _videoPlayerController?.setVolume(appVolume * 100);

      // 显示提示
      SmartDialog.showToast('已切换到应用内音量模式');
    } else {
      // 切换到同步系统音量模式
      // 恢复上游播放器音量设置，并按增益折算系统音量
      final currentSystemVolume =
          (await FlutterVolumeController.getVolume()) ?? 1.0;
      final playerGain = max(Pref.playerVolume / 100, 0.01);
      final newSystemVolume = (currentSystemVolume * volume.value / playerGain)
          .clamp(0.0, 1.0)
          .toDouble();

      await FlutterVolumeController.updateShowSystemUI(false);
      await FlutterVolumeController.setVolume(newSystemVolume);
      await _videoPlayerController?.setVolume(Pref.playerVolume);
      volumeBoostUnlocked = false;

      // 更新状态
      systemVolume.value = newSystemVolume;
      volume.value = newSystemVolume;

      SmartDialog.showToast('已切换到同步系统音量模式');
    }
  }

  /// duck 事件处理（由 audio_session.dart 调用）
  Future<void> handleDuck(bool begin) async {
    if (!PlatformUtils.isMobile) return;

    if (Pref.enableAppVolume) {
      // 应用内音量模式：使用临时音量，不影响持久化值
      if (begin) {
        _isDucked = true;
        _preDuckVolume = volume.value;
        volume.value = volume.value * 0.5;
        _videoPlayerController?.setVolume(volume.value * 100);
      } else {
        _isDucked = false;
        volume.value = _preDuckVolume;
        _videoPlayerController?.setVolume(volume.value * 100);
      }
    }
    // 同步模式：使用原有逻辑，直接调用 setVolume 即可
  }

  /// Toggle Change the videofit accordingly
  void toggleVideoFit(VideoFitType value) {
    _prefFit = videoFit.value = value;
    video.put(VideoBoxKey.cacheVideoFit, value.index);
  }

  /// 读取fit
  var _prefFit = VideoFitType.values[Pref.cacheVideoFit];
  void _initVideoFit() {
    if (_prefFit == .fill && _isVertical) {
      videoFit.value = .contain;
    } else {
      videoFit.value = _prefFit;
    }
  }

  /// 设置后台播放
  void setBackgroundPlay(bool val) {
    videoPlayerServiceHandler?.enableBackgroundPlay = val;
    if (!val) {
      videoPlayerServiceHandler?.forceClear();
    }
    if (!tempPlayerConf) {
      setting.put(SettingBoxKey.enableBackgroundPlay, val);
    }
  }

  void syncBackgroundMediaSession() {
    final handler = videoPlayerServiceHandler;
    if (handler == null || !handler.enableBackgroundPlay) {
      return;
    }
    handler
      ..onStatusChange(playerStatus.value, isBuffering.value, isLive)
      ..onPositionChange(Duration(seconds: position.value));
  }

  set controls(bool visible) {
    showControls.value = visible;
    _sourceCoordinator.releaseSourceTimer(_timer, cancel: true);
    _timer = null;
    if (visible) {
      hideTaskControls();
    }
  }

  Timer? _longPressTimer;
  Timer? get longPressTimer => _longPressTimer;
  set longPressTimer(Timer? value) {
    _sourceCoordinator.releaseSourceTimer(_longPressTimer);
    _longPressTimer = value;
    if (value != null) {
      _sourceCoordinator.trackSourceTimer(value);
    }
  }

  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }

  /// 设置长按倍速状态 live模式下禁用
  Future<void> setLongPressStatus(bool val) async {
    if (isLive) {
      return;
    }
    if (controlsLock.value) {
      return;
    }
    if (longPressStatus.value == val) {
      return;
    }
    if (val) {
      if (playerStatus.isPlaying) {
        longPressStatus.value = val;
        HapticFeedback.lightImpact();
        await setPlaybackSpeed(
          enableAutoLongPressSpeed ? playbackSpeed * 2 : longPressSpeed,
        );
      }
    } else {
      longPressStatus.value = val;
      await setPlaybackSpeed(lastPlaybackSpeed);
    }
  }

  bool get isCompleted =>
      videoPlayerController!.state.completed ||
      durationInMilliseconds - positionInMilliseconds <= 50;

  // 双击播放、暂停
  Future<void> onDoubleTapCenter() async {
    if (!isLive && isCompleted) {
      await videoPlayerController!.seek(Duration.zero);
      videoPlayerController!.play();
    } else {
      videoPlayerController!.playOrPause();
    }
  }

  final RxBool mountSeekBackwardButton = false.obs;
  final RxBool mountSeekForwardButton = false.obs;

  void onDoubleTapSeekBackward() {
    mountSeekBackwardButton.value = true;
  }

  void onDoubleTapSeekForward() {
    mountSeekForwardButton.value = true;
  }

  void onForward(Duration duration) {
    onForwardBackward(videoPlayerController!.state.position + duration);
  }

  void onBackward(Duration duration) {
    onForwardBackward(videoPlayerController!.state.position - duration);
  }

  void onForwardBackward(Duration duration) {
    seekTo(
      duration.clamp(Duration.zero, videoPlayerController!.state.duration),
      isSeek: false,
    ).whenComplete(play);
  }

  void doubleTapFuc(DoubleTapType type) {
    if (!enableQuickDouble) {
      onDoubleTapCenter();
      return;
    }
    switch (type) {
      case DoubleTapType.left:
        // 双击左边区域 👈
        onDoubleTapSeekBackward();
        break;
      case DoubleTapType.center:
        onDoubleTapCenter();
        break;
      case DoubleTapType.right:
        // 双击右边区域 👈
        onDoubleTapSeekForward();
        break;
    }
  }

  /// 关闭控制栏
  void onLockControl(bool val) {
    feedBack();
    controlsLock.value = val;
    if (!val && showControls.value) {
      showControls.refresh();
    }
    controls = !val;
  }

  void _setFullScreen(bool val) {
    isFullScreen.value = val;
    updateSubtitleStyle();
    onFullScreenChanged?.call(val);
  }

  double screenRatio = 0.0;
  bool isManualFS = true;
  late final FullScreenMode mode = Pref.fullScreenMode;
  late final horizontalScreen = Pref.horizontalScreen;
  late final removeSafeArea = Pref.removeSafeArea;

  Future<void>? changeOrientation({
    required bool isVertical,
    DeviceOrientation? orientation,
  }) {
    if (orientation == null && (mode == .none || mode == .gravity)) {
      return null;
    }
    if (orientation == null &&
        (mode == .vertical ||
            (mode == .auto && isVertical) ||
            (mode == .ratio && (isVertical || screenRatio < kScreenRatio)))) {
      return portraitUpMode();
    } else {
      // https://github.com/flutter/flutter/issues/73651
      // https://github.com/flutter/flutter/issues/183708
      if (Platform.isAndroid) {
        if ((orientation ?? _orientation) == .landscapeRight) {
          return landscapeRightMode();
        } else {
          return landscapeLeftMode();
        }
      } else {
        if (orientation == .landscapeLeft) {
          return landscapeLeftMode();
        } else {
          return landscapeRightMode();
        }
      }
    }
  }

  // 全屏
  bool _fsProcessing = false;
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  }) async {
    if (isDesktopPip) return;
    if (isFullScreen.value == status) return;

    if (_fsProcessing) return;
    _fsProcessing = true;
    this.isManualFS = isManualFS;
    try {
      if (status) {
        if (PlatformUtils.isMobile) {
          hideSystemBar();
          await changeOrientation(
            isVertical: isVertical,
            orientation: orientation,
          );
        } else {
          await enterDesktopFullScreen(inAppFullScreen: inAppFullScreen);
        }
      } else {
        if (PlatformUtils.isMobile) {
          if (!removeSafeArea) {
            showSystemBar();
          }
          if (orientation == null && mode == .none) {
            return;
          }
          await resetScreenRotation();
        } else {
          await exitDesktopFullScreen();
        }
      }
    } finally {
      _setFullScreen(status);
      _fsProcessing = false;
    }
  }

  void addPositionListener(ValueChanged<Duration> listener) {
    if (_playerCount == 0) return;
    _positionListeners.add(listener);
  }

  void removePositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.remove(listener);

  void addSeekListener(ValueChanged<Duration> listener) {
    if (_playerCount == 0) return;
    _seekListeners.add(listener);
  }

  void removeSeekListener(ValueChanged<Duration> listener) =>
      _seekListeners.remove(listener);

  void addStatusLister(ValueChanged<PlayerStatus> listener) {
    if (_playerCount == 0) return;
    _statusListeners.add(listener);
  }

  void removeStatusLister(ValueChanged<PlayerStatus> listener) =>
      _statusListeners.remove(listener);

  // 记录播放记录
  Future<void>? makeHeartBeat(
    int progress, {
    HeartBeatType type = .playing,
    bool isManual = false,
    dynamic aid,
    dynamic bvid,
    dynamic cid,
    dynamic epid,
    dynamic seasonId,
    dynamic pgcType,
    VideoType? videoType,
  }) {
    if (!isManual && dataStatus.value != DataStatus.loaded) {
      return null;
    }
    if (isLive ||
        !enableHeart ||
        progress == 0 ||
        (playerStatus.isPaused && !isManual)) {
      return null;
    }

    Future<void> send() {
      return VideoHttp.heartBeat(
        aid: aid ?? _aid,
        bvid: bvid ?? _bvid,
        cid: cid ?? this.cid,
        progress: progress,
        epid: epid ?? _epid,
        seasonId: seasonId ?? _seasonId,
        subType: pgcType ?? _pgcType,
        videoType: videoType ?? _videoType,
      );
    }

    switch (type) {
      case .playing:
        if (progress - _heartDuration >= 5) {
          _heartDuration = progress;
          return send();
        }
      case .status:
        if (progress - _heartDuration >= 2) {
          _heartDuration = progress;
          return send();
        }
      case .completed:
        if (playerStatus.isCompleted &&
            (durationInMilliseconds - positionInMilliseconds) <= 1000) {
          progress = -1;
        }
        return send();
    }
    return null;
  }

  void setPlayRepeat(PlayRepeat type) {
    playRepeat = type;
    if (!tempPlayerConf) video.put(VideoBoxKey.playRepeat, type.index);
  }

  void putSubtitleSettings() {
    setting.putAllNE({
      SettingBoxKey.subtitleFontScale: subtitleFontScale,
      SettingBoxKey.subtitleFontScaleFS: subtitleFontScaleFS,
      SettingBoxKey.subtitlePaddingH: subtitlePaddingH,
      SettingBoxKey.subtitlePaddingB: subtitlePaddingB,
      SettingBoxKey.subtitleBgOpacity: subtitleBgOpacity,
      SettingBoxKey.subtitleStrokeWidth: subtitleStrokeWidth,
      SettingBoxKey.subtitleFontWeight: subtitleFontWeight,
      SettingBoxKey.subtitleSecondaryFontScale: subtitleSecondaryFontScale,
      SettingBoxKey.subtitleSecondaryFontScaleFS: subtitleSecondaryFontScaleFS,
      SettingBoxKey.subtitleSecondaryBgOpacity: subtitleSecondaryBgOpacity,
      SettingBoxKey.subtitleSecondaryStrokeWidth: subtitleSecondaryStrokeWidth,
      SettingBoxKey.subtitleSecondaryFontWeight: subtitleSecondaryFontWeight,
      SettingBoxKey.subtitleSecondarySpacing: subtitleSecondarySpacing,
    });
  }

  bool _isCloseAll = false;
  bool get isCloseAll => _isCloseAll;

  Future<void>? resetScreenRotation() {
    if (horizontalScreen) {
      return fullMode();
    } else {
      return portraitUpMode();
    }
  }

  void onCloseAll() {
    _isCloseAll = true;
    try {
      Get.find<MainController>().toHomePage();
    } catch (_) {}
    dispose();
    Get.until((route) => route.isFirst);
  }

  void dispose() {
    // 每次减1，最后销毁
    resetScreenRotation();
    cancelLongPressTimer();
    _cancelSubForSeek();
    if (!_isCloseAll && _playerCount > 1) {
      _playerCount -= 1;
      _heartDuration = 0;
      return;
    }

    _playerCount = 0;
    _sourceCoordinator.dispose();
    if (removeSafeArea) {
      showSystemBar();
    }
    danmakuController = null;
    _stopOrientationListener();
    _disableAutoEnterPip();
    setPlayCallBack(null);
    dmState.clear();
    if (showSeekPreview) {
      _clearPreview();
    }
    if (Platform.isAndroid) {
      AndroidHelper$ToDart.onUserLeaveHint?.release();
      AndroidHelper$ToDart.onUserLeaveHint = null;
    }
    // _position.close();
    // _playerEventSubs?.cancel();
    // _sliderPosition.close();
    // _sliderTempPosition.close();
    // _isSliderMoving.close();
    // _duration.close();
    // _buffered.close();
    // _showControls.close();
    // _controlsLock.close();

    // playerStatus.close();
    // dataStatus.close();

    if (PlatformUtils.isDesktop && isAlwaysOnTop.value) {
      windowManager.setAlwaysOnTop(false);
    }

    _positionListeners.clear();
    _seekListeners.clear();
    _statusListeners.clear();
    if (playerStatus.isPlaying) {
      WakelockPlus.disable();
    }
    if (kDebugMode) {
      debugPrint('dispose player');
    }
    final player = _videoPlayerController;
    _videoPlayerController = null;
    _videoController = null;
    if (player != null) {
      unawaited(
        Future<void>.sync(player.dispose).then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (kDebugMode) {
              debugPrint(stackTrace.toString());
              debugPrint(
                'PlPlayer final dispose failed (${error.runtimeType})',
              );
            }
          },
        ),
      );
    }
    _activeVideoContextKey = null;
    _instance = null;
    videoPlayerServiceHandler?.clear();
  }

  static void updatePlayCount() {
    if (_instance?._playerCount == 1) {
      _instance?.dispose();
    } else {
      _instance?._playerCount -= 1;
    }
  }

  void setContinuePlayInBackground({VoidCallback? onEnable}) {
    final enable = !continuePlayInBackground.value;
    continuePlayInBackground.value = enable;
    if (!tempPlayerConf) {
      setting.put(SettingBoxKey.continuePlayInBackground, enable);
    }
    if (enable) {
      setBackgroundPlay(true);
      onEnable?.call();
      syncBackgroundMediaSession();
      unawaited(audioSessionHandler?.setActive(playerStatus.isPlaying));
    } else {
      videoPlayerServiceHandler?.forceClear();
      unawaited(audioSessionHandler?.setActive(false));
    }
  }

  Future<void>? applyOnlyPlayAudioTrack() {
    return videoPlayerController?.setVideoTrack(
      onlyPlayAudio.value ? VideoTrack.no() : VideoTrack.auto(),
    );
  }

  void setOnlyPlayAudio() {
    onlyPlayAudio.value = !onlyPlayAudio.value;
    applyOnlyPlayAudioTrack();
  }

  late final Map<String, ui.Image?> previewCache = {};
  final PreviewRequestEpoch _previewRequestEpoch = PreviewRequestEpoch();
  LoadingState<VideoShotData>? videoShot;
  late final RxBool showPreview = false.obs;
  late final showSeekPreview = Pref.showSeekPreview;
  late final previewIndex = RxnInt();

  PreviewRequestToken capturePreviewRequest(String url) =>
      _previewRequestEpoch.capture(url);

  bool isPreviewRequestCurrent(PreviewRequestToken token) =>
      _previewRequestEpoch.isCurrent(token);

  void updatePreviewIndex(int seconds) {
    if (videoShot == null) {
      videoShot = LoadingState.loading();
      getVideoShot();
      return;
    }
    if (videoShot case Success(:final response)) {
      showPreview.value = true;
      previewIndex.value = max(
        0,
        (response.index.where((item) => item <= seconds).length - 2),
      );
    }
  }

  void _clearPreview() {
    _previewRequestEpoch.invalidate();
    showPreview.value = false;
    previewIndex.value = null;
    videoShot = null;
    for (final i in previewCache.values) {
      i?.dispose();
    }
    previewCache.clear();
  }

  Future<void> getVideoShot() async {
    final generation = _activeSourceGeneration;
    final sourceBvid = _bvid;
    final sourceCid = cid;
    if (generation == null || sourceBvid == null || sourceCid == null) {
      videoShot = null;
      return;
    }

    final result = await VideoHttp.videoshot(
      bvid: sourceBvid,
      cid: sourceCid,
    );
    if (_sourceCoordinator.isActive(generation) &&
        _bvid == sourceBvid &&
        cid == sourceCid) {
      videoShot = result;
    }
  }

  BuildContext? _screenshotDialogContext;
  int? _screenshotDialogGeneration;

  void _dismissSourceScopedScreenshot() {
    final context = _screenshotDialogContext;
    _screenshotDialogContext = null;
    _screenshotDialogGeneration = null;
    if (context != null && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> takeScreenshot() async {
    final generation = _activeSourceGeneration;
    final player = videoPlayerController;
    final sourceCid = cid;
    if (generation == null || player == null) {
      SmartDialog.showToast('截图失败');
      return;
    }
    _dismissSourceScopedScreenshot();
    SmartDialog.showToast('截图中');
    final time = DurationUtils.formatDuration(
      positionInMilliseconds / 1000,
    ).replaceAll(':', '-');
    final image = await player.screenshot();
    if (!_sourceCoordinator.isActive(generation) ||
        !identical(videoPlayerController, player)) {
      image?.dispose();
      return;
    }
    if (image != null) {
      SmartDialog.showToast('点击弹窗保存截图');
      final rootContext = Get.context;
      if (rootContext == null || !rootContext.mounted) {
        image.dispose();
        return;
      }
      try {
        await showDialog<void>(
          context: rootContext,
          builder: (context) {
            if (!_sourceCoordinator.isActive(generation)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              });
              return const SizedBox.shrink();
            }
            _screenshotDialogContext = context;
            _screenshotDialogGeneration = generation;
            return GestureDetector(
              onTap: () async {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (bytes != null && _sourceCoordinator.isActive(generation)) {
                  ImageUtils.saveByteImg(
                    bytes: bytes.buffer.asUint8List(),
                    fileName: 'screenshot_${sourceCid}_$time',
                  );
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: min(MediaQuery.widthOf(context) / 3, 350),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 5,
                          color: ColorScheme.of(context).surface,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: RawImage(image: image),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      } finally {
        if (_screenshotDialogGeneration == generation) {
          _screenshotDialogContext = null;
          _screenshotDialogGeneration = null;
        }
        image.dispose();
      }
    } else {
      SmartDialog.showToast('截图失败');
    }
  }

  void onPopInvokedWithResult(
    bool didPop,
    Object? result, {
    bool pauseOnPop = true,
  }) {
    if (didPop) {
      if (pauseOnPop && playerStatus.isPlaying) {
        pause();
      }

      setPlayCallBack(null);

      if (Platform.isAndroid && _playerCount <= 1) {
        _disableAutoEnterPip();
        if (!setSystemBrightness) {
          ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
        }
      }

      return;
    }

    if (controlsLock.value) {
      onLockControl(false);
      return;
    }
    if (isDesktopPip) {
      exitDesktopPip();
      return;
    }
    if (isPipMode) {
      return;
    }
    if (isFullScreen.value) {
      triggerFullScreen(status: false);
      return;
    }
    Get.back();
  }
}
