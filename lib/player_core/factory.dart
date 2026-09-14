import 'package:PiliPlus/player_core/backends/media3_core.dart';
import 'package:PiliPlus/player_core/backends/mpv_core.dart';
import 'package:PiliPlus/player_core/backends/vlc_core.dart';
import 'package:PiliPlus/player_core/core_player.dart';

/// 内核工厂（bv PlayerFactory 的 Dart 移植）。
abstract final class CorePlayerFactory {
  static CorePlayer create(PlayerBackend backend) => switch (backend) {
    PlayerBackend.mpv => MpvCorePlayer(),
    PlayerBackend.media3 => Media3CorePlayer(),
    PlayerBackend.vlc => VlcCorePlayer(),
  };
}
