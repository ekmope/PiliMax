import 'dart:async';

import 'package:PiliPlus/player_core/core_player.dart';
import 'package:PiliPlus/player_core/factory.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 三内核统一播放页（bv 播放器架构的 Flutter 实现）。
/// 供源订阅内容与内核切换播放使用。
class CoreVideoController extends GetxController {
  CoreVideoController({
    required this.source,
    required this.title,
    this.startBackend,
  });

  final CoreMediaSource source;
  final String title;
  final PlayerBackend? startBackend;

  late final Rx<CorePlayer> player;
  final Rx<CorePlayerState> state = const CorePlayerState().obs;
  final Rx<PlayerBackend> backend = PlayerBackend.mpv.obs;
  final RxBool showControls = true.obs;
  StreamSubscription? _sub;
  Timer? _hideTimer;

  @override
  void onInit() {
    super.onInit();
    backend.value =
        startBackend ?? PlayerBackend.fromName(Pref.defaultPlayerBackend);
    player = CorePlayerFactory.create(backend.value).obs;
    _start();
  }

  Future<void> _start() async {
    final p = player.value;
    await p.init();
    _sub = p.stateStream.listen((s) => state.value = s);
    await p.setDataSource(source);
    await p.play();
    _autoHide();
  }

  /// 切换内核：保留进度重建实例（bv 切换机制）。
  Future<void> switchBackend(PlayerBackend target) async {
    if (target == backend.value) return;
    final pos = state.value.position;
    final wasPlaying = state.value.isPlaying;
    final speed = state.value.speed;

    await _sub?.cancel();
    final old = player.value;
    await old.dispose();

    backend.value = target;
    final next = CorePlayerFactory.create(target);
    player.value = next;
    await next.init();
    _sub = next.stateStream.listen((s) => state.value = s);
    await next.setDataSource(
      CoreMediaSource(
        videoUrl: source.videoUrl,
        audioUrl: source.audioUrl,
        videoIndexRange: source.videoIndexRange,
        videoInitRange: source.videoInitRange,
        audioIndexRange: source.audioIndexRange,
        audioInitRange: source.audioInitRange,
        videoCodecs: source.videoCodecs,
        audioCodecs: source.audioCodecs,
        bandwidth: source.bandwidth,
        durationMs: source.durationMs,
        headers: source.headers,
        startPosition: pos,
        isLive: source.isLive,
      ),
    );
    await next.setSpeed(speed);
    if (wasPlaying) {
      await next.play();
    } else {
      await next.pause();
    }
  }

  void togglePlay() {
    if (state.value.isPlaying) {
      player.value.pause();
    } else {
      player.value.play();
    }
    _autoHide();
  }

  void seek(Duration position) {
    player.value.seekTo(position);
    _autoHide();
  }

  void setSpeed(double speed) {
    player.value.setSpeed(speed);
    _autoHide();
  }

  void toggleControls() {
    showControls.value = !showControls.value;
    if (showControls.value) _autoHide();
  }

  void _autoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      showControls.value = false;
    });
  }

  @override
  void onClose() {
    _hideTimer?.cancel();
    _sub?.cancel();
    player.value.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.onClose();
  }
}

class CoreVideoPage extends StatelessWidget {
  const CoreVideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CoreVideoController>();
    final colorScheme = ColorScheme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: controller.toggleControls,
          child: Stack(
            children: [
              Center(
                child: Obx(() => controller.player.value.buildView()),
              ),
              Obx(
                () => controller.showControls.value
                    ? _buildControls(context, controller, colorScheme)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    CoreVideoController controller,
    ColorScheme colorScheme,
  ) {
    return Obx(
      () {
        final s = controller.state.value;
        return Column(
          children: [
            // 顶栏：标题 + 内核切换
            AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text(
                controller.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                PopupMenuButton<String>(
                  color: colorScheme.surfaceContainerHigh,
                  icon: const Icon(Icons.memory, color: Colors.white),
                  tooltip: '切换内核',
                  onSelected: (value) =>
                      controller.switchBackend(PlayerBackend.fromName(value)),
                  itemBuilder: (context) => [
                    for (final b in PlayerBackend.values)
                      PopupMenuItem(
                        value: b.name,
                        child: Row(
                          children: [
                            Icon(
                              controller.backend.value == b
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 18,
                              color: controller.backend.value == b
                                  ? colorScheme.primary
                                  : colorScheme.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(b.label),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            // 中央播放按钮
            Center(
              child: IconButton(
                iconSize: 56,
                color: Colors.white70,
                icon: Icon(
                  s.isBuffering
                      ? Icons.progress_indicator
                      : s.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                ),
                onPressed: controller.togglePlay,
              ),
            ),
            const Spacer(),
            // 底栏：进度 + 倍速
            Container(
              padding: const .only(left: 12, right: 12, bottom: 16),
              color: Colors.black54,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    Row(
                      children: [
                        Text(
                          DurationUtils.formatDuration(
                            s.position.inMilliseconds / 1000,
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: s.duration.inMilliseconds > 0
                                ? s.position.inMilliseconds
                                      .clamp(
                                        0,
                                        s.duration.inMilliseconds,
                                      )
                                      .toDouble()
                                : 0,
                            max:
                                s.duration.inMilliseconds > 0
                                ? s.duration.inMilliseconds.toDouble()
                                : 1,
                            onChanged: (value) => controller.seek(
                              Duration(milliseconds: value.toInt()),
                            ),
                          ),
                        ),
                        Text(
                          DurationUtils.formatDuration(
                            s.duration.inMilliseconds / 1000,
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        if (s.tcpSpeed > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${(s.tcpSpeed / 1024).toStringAsFixed(0)}KB/s',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        PopupMenuButton<double>(
                          color: colorScheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const .symmetric(horizontal: 8),
                            child: Text(
                              '${s.speed}x',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          onSelected: controller.setSpeed,
                          itemBuilder: (context) => [
                            for (final speed in const [
                              0.5,
                              0.75,
                              1.0,
                              1.25,
                              1.5,
                              2.0,
                              3.0,
                            ])
                              PopupMenuItem(
                                value: speed,
                                child: Text(
                                  speed == speed.roundToDouble()
                                      ? '${speed.toInt()}x'
                                      : '${speed}x',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (s.error case final err?)
                      Text(
                        err,
                        style: TextStyle(color: colorScheme.error, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
