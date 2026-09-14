import 'dart:async';

import 'package:PiliPlus/player_core/core_player.dart';
import 'package:PiliPlus/player_core/dash_manifest.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show DurationRange;

/// Media3/ExoPlayer 内核（video_player）：
/// DASH 分离流经合成 MPD + 本地 HTTP 服务播放（bv 方案的 Dart 移植）。
class Media3CorePlayer implements CorePlayer {
  final _stateController = StreamController<CorePlayerState>.broadcast();
  VideoPlayerController? _controller;
  VoidCallback? _listener;
  CoreMediaSource? _source;

  @override
  PlayerBackend get backend => PlayerBackend.media3;

  @override
  Future<void> init() async {}

  @override
  Future<void> setDataSource(CoreMediaSource source) async {
    _source = source;
    await _controller?.dispose();
    _controller = null;

    Uri uri;
    Map<String, String> headers = Map.of(source.headers);
    if (source.hasSeparateAudio) {
      // DASH：合成 MPD 清单并经本地服务提供
      uri = Uri.parse(await DashManifestServer.instance.ensureUrl(source));
    } else {
      uri = Uri.parse(source.videoUrl ?? source.audioUrl ?? '');
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: headers,
    );
    _controller = controller;

    _listener = () {
      final v = controller.value;
      _stateController.add(
        CorePlayerState(
          position: v.position,
          duration: v.duration,
          buffered: _maxBufferedEnd(v.buffered, v.position),
          isPlaying: v.isPlaying,
          isBuffering: v.isBuffering,
          isCompleted: v.position >= v.duration && v.duration > Duration.zero,
          speed: v.playbackSpeed,
          volume: v.volume,
          error: v.errorDescription,
          width: v.size.width.toInt(),
          height: v.size.height.toInt(),
        ),
      );
    };
    controller.addListener(_listener!);
    await controller.initialize();
    if (source.startPosition case final pos? when pos > Duration.zero) {
      await controller.seekTo(pos);
    }
  }

  Duration _maxBufferedEnd(List<DurationRange> ranges, Duration current) {
    Duration max = Duration.zero;
    for (final r in ranges) {
      if (r.end > current && r.end > max) max = r.end;
    }
    return max;
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async =>
      _controller?.seekTo(position);

  @override
  Future<void> setSpeed(double speed) async =>
      _controller?.setPlaybackSpeed(speed);

  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume(volume);

  @override
  CorePlayerState get state {
    final v = _controller?.value;
    if (v == null) return const CorePlayerState();
    return CorePlayerState(
      position: v.position,
      duration: v.duration,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      speed: v.playbackSpeed,
      volume: v.volume,
      error: v.errorDescription,
      width: v.size.width.toInt(),
      height: v.size.height.toInt(),
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
    return VideoPlayer(controller);
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    if (_listener != null && controller != null) {
      controller.removeListener(_listener!);
    }
    await controller?.dispose();
    _controller = null;
    await _stateController.close();
  }
}
