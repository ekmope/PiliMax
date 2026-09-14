import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 播放内核类型（bv 三大播放器）
enum PlayerBackend with EnumWithLabel {
  mpv('MPV'),
  media3('Media3'),
  vlc('VLC');

  final String label;
  const PlayerBackend(this.label);

  static PlayerBackend fromName(String? name) => switch (name) {
    'media3' => PlayerBackend.media3,
    'vlc' => PlayerBackend.vlc,
    _ => PlayerBackend.mpv,
  };
}

/// 播放源：直链（音视频可分离）或本地 MPD 清单。
class CoreMediaSource {
  /// 视频流直链（DASH 分离流时的视频 URL，或单流的唯一 URL）
  final String? videoUrl;

  /// 音频流直链（DASH 分离流时非空）
  final String? audioUrl;

  /// 视频流字节区间（fMP4 init/index，供 MPD 合成）
  final String? videoIndexRange;
  final String? videoInitRange;
  final String? audioIndexRange;
  final String? audioInitRange;

  /// 视频编码（MPD Representation codecs）
  final String? videoCodecs;
  final String? audioCodecs;
  final int? bandwidth;

  /// 总时长（毫秒，MPD mediaPresentationDuration）
  final int? durationMs;

  final Map<String, String> headers;
  final Duration? startPosition;
  final bool isLive;

  const CoreMediaSource({
    this.videoUrl,
    this.audioUrl,
    this.videoIndexRange,
    this.videoInitRange,
    this.audioIndexRange,
    this.audioInitRange,
    this.videoCodecs,
    this.audioCodecs,
    this.bandwidth,
    this.durationMs,
    this.headers = const {},
    this.startPosition,
    this.isLive = false,
  });

  bool get hasSeparateAudio =>
      audioUrl != null && audioUrl!.isNotEmpty && videoUrl != null;
}

/// 内核上报的播放状态。
class CorePlayerState {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final double speed;
  final double volume;
  final String? error;
  final int width;
  final int height;
  /// 实时网速（字节/秒），内核不支持时为 0
  final int tcpSpeed;

  const CorePlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.speed = 1.0,
    this.volume = 1.0,
    this.error,
    this.width = 0,
    this.height = 0,
    this.tcpSpeed = 0,
  });
}

/// 播放内核统一抽象（bv AbstractVideoPlayer 的 Dart 移植）。
abstract class CorePlayer {
  PlayerBackend get backend;

  /// 初始化内核实例
  Future<void> init();

  /// 设置数据源并准备播放（不自动开始）。
  /// 契约与 bv 一致：纯设置操作，不中断当前播放；prepare 消费该地址。
  Future<void> setDataSource(CoreMediaSource source);

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);

  CorePlayerState get state;

  Stream<CorePlayerState> get stateStream;

  /// 该内核的渲染视图
  Widget buildView({ BoxFit fit = BoxFit.contain });

  Future<void> dispose();
}
