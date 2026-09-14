import 'dart:async';

import 'package:PiliPlus/player_core/core_player.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// MPV 内核（media_kit）：默认内核，支持 DASH 分离流（EDL）与全部播放优化。
class MpvCorePlayer implements CorePlayer {
  MpvCorePlayer({Map<String, String>? headers})
    : _extraHeaders = headers ?? const {};

  final Map<String, String> _extraHeaders;
  Player? _player;
  VideoController? _videoController;
  final _stateController = StreamController<CorePlayerState>.broadcast();
  CorePlayerState _state = const CorePlayerState();
  Timer? _pollTimer;
  double _speed = 1.0;

  void _ensurePolling() {
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      _stateController.add(state);
    });
  }

  @override
  PlayerBackend get backend => PlayerBackend.mpv;

  @override
  Future<void> init() async {
    if (_player != null) return;
    final player = await Player.create();
    _videoController = await VideoController.create(player);
    _player = player;
  }

  @override
  Future<void> setDataSource(CoreMediaSource source) async {
    _ensurePolling();
    final player = _player;
    if (player == null) return;

    var url = source.videoUrl ?? '';
    if (source.hasSeparateAudio) {
      // EDL 合成音视频分离流（与 pl_player 相同的 mpv 方案）
      final video = source.videoUrl!;
      final audio = source.audioUrl!;
      url =
          'edl://'
          '!no_chapters;'
          '%${video.length}%$video;'
          '!new_stream;!no_chapters;'
          '%${audio.length}%$audio';
    }

    await player.open(
      Media(
        url,
        start: source.startPosition,
        extras: <String, dynamic>{
          if (source.headers.isNotEmpty || _extraHeaders.isNotEmpty)
            'headers': <String, String>{
              ...source.headers,
              ..._extraHeaders,
            },
        },
      ),
      play: false,
    );
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seekTo(Duration position) async =>
      _player?.seek(position);

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player?.setRate(speed);
  }

  @override
  Future<void> setVolume(double volume) async =>
      _player?.setVolume(volume * 100);

  @override
  CorePlayerState get state {
    final player = _player;
    if (player == null) return _state;
    return CorePlayerState(
      position: player.state.position,
      duration: player.state.duration,
      buffered: player.state.buffer,
      isPlaying: player.state.playing,
      isBuffering: player.state.buffering,
      isCompleted: player.state.completed,
      speed: _speed,
      volume: player.state.volume / 100,
      width: player.state.width,
      height: player.state.height,
    );
  }

  @override
  Stream<CorePlayerState> get stateStream => _stateController.stream;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    final controller = _videoController;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return Video(
      controller: controller,
      fit: switch (fit) {
        BoxFit.cover => BoxFit.cover,
        BoxFit.fill => BoxFit.fill,
        _ => BoxFit.contain,
      },
    );
  }

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _player?.dispose();
    _player = null;
    _videoController = null;
    await _stateController.close();
  }
}
