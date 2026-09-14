import 'dart:async';

import 'package:PiliPlus/player_core/core_player.dart';
import 'package:PiliPlus/player_core/dash_manifest.dart';
import 'package:flutter/widgets.dart';
import 'package:vlc_player/vlc_player.dart';

/// VLC 内核（vlc_player）：DASH 分离流同样走合成 MPD（bv VlcDashManifest 方案）。
class VlcCorePlayer implements CorePlayer {
  final _stateController = StreamController<CorePlayerState>.broadcast();
  VlcPlayerController? _controller;
  Timer? _statsTimer;

  @override
  PlayerBackend get backend => PlayerBackend.vlc;

  @override
  Future<void> init() async {}

  @override
  Future<void> setDataSource(CoreMediaSource source) async {
    _controller?.dispose();
    _controller = null;
    _statsTimer?.cancel();

    Uri uri;
    if (source.hasSeparateAudio) {
      uri = Uri.parse(await DashManifestServer.instance.ensureUrl(source));
    } else {
      uri = Uri.parse(source.videoUrl ?? source.audioUrl ?? '');
    }

    final controller = VlcPlayerController(
      mediaSource: VlcMediaSource(
        uri: uri,
        httpHeaders: source.headers,
        startPosition: source.startPosition ?? Duration.zero,
        mediaOptions: source.isLive
            ? const [':network-caching=800']
            : const [':network-caching=1200'],
      ),
      autoPlay: false,
    );
    _controller = controller;
    controller.addListener(_onVlcValue);

    // 周期采集网速（VLC inputBitrate）
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_controller == null) return;
      try {
        final stats = await controller.getMediaStats();
        if (stats.isAvailable && stats.inputBitrate > 0) {
          _stateController.add(
            state.copyWith(tcpSpeed: (stats.inputBitrate * 1024 ~/ 8)),
          );
        }
      } catch (_) {}
    });
  }

  void _onVlcValue() {
    final v = _controller?.value;
    if (v == null) return;
    _stateController.add(
      CorePlayerState(
        position: v.position,
        duration: v.duration,
        isPlaying: v.isPlaying,
        isBuffering: v.isBuffering,
        isCompleted: v.state == VlcPlaybackState.ended,
        volume: (v.volume / 100).clamp(0.0, 2.0),
        error: v.hasError ? (v.errorDescription ?? 'VLC error') : null,
      ),
    );
  }

  @override
  Future<void> play() async {
    try {
      await _controller?.play();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try {
      await _controller?.pause();
    } catch (_) {}
  }

  @override
  Future<void> seekTo(Duration position) async {
    try {
      await _controller?.seekTo(position);
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      await _controller?.setPlaybackSpeed(speed);
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _controller?.setVolume((volume * 100).round().clamp(0, 200));
    } catch (_) {}
  }

  @override
  CorePlayerState get state {
    final v = _controller?.value;
    if (v == null) return const CorePlayerState();
    return CorePlayerState(
      position: v.position,
      duration: v.duration,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      isCompleted: v.state == VlcPlaybackState.ended,
      volume: (v.volume / 100).clamp(0.0, 2.0),
      error: v.hasError ? (v.errorDescription ?? 'VLC error') : null,
    );
  }

  @override
  Stream<CorePlayerState> get stateStream => _stateController.stream;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return VlcPlayer(
      controller: controller,
      fit: switch (fit) {
        BoxFit.cover => VlcVideoFit.cover,
        BoxFit.fill => VlcVideoFit.fill,
        _ => VlcVideoFit.contain,
      },
    );
  }

  @override
  Future<void> dispose() async {
    _statsTimer?.cancel();
    _controller?.removeListener(_onVlcValue);
    _controller?.dispose();
    _controller = null;
    await _stateController.close();
  }
}

extension on CorePlayerState {
  CorePlayerState copyWith({int? tcpSpeed}) => CorePlayerState(
    position: position,
    duration: duration,
    buffered: buffered,
    isPlaying: isPlaying,
    isBuffering: isBuffering,
    isCompleted: isCompleted,
    speed: speed,
    volume: volume,
    error: error,
    width: width,
    height: height,
    tcpSpeed: tcpSpeed ?? this.tcpSpeed,
  );
}
