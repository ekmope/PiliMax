import 'dart:async' show unawaited;
import 'dart:io';

import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession session;
  late final Future<void> _initialized;
  Future<void> _operationQueue = Future<void>.value();
  bool _playInterrupted = false;
  bool _forceMixWithOthers = false;

  bool get mixWithOthers => Pref.mixWithOthers || _forceMixWithOthers;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final run = _operationQueue.then<T>(
      (_) => operation(),
      onError: (Object _, StackTrace _) => operation(),
    );
    _operationQueue = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return run;
  }

  Future<bool> setActive(bool active) {
    return _enqueue(() async {
      await _initialized;
      return session.setActive(active);
    });
  }

  AudioSessionHandler() {
    _initialized = _initSession();
  }

  Future<void> _configureSession() async {
    if (mixWithOthers && Platform.isIOS) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        ),
      );
    } else {
      await session.configure(const AudioSessionConfiguration.music());
    }
  }

  Future<void> reconfigure({bool? active}) async {
    await _enqueue(() async {
      await _initialized;
      final controller = PlPlayerController.instance;
      final shouldActivate =
          active ??
          (controller?.hasPlaybackIntent ?? false);
      await session.setActive(false);
      await _configureSession();
      if (shouldActivate) {
        await session.setActive(true);
      }
    });
  }

  void cancelInterruptedPlayback() {
    _playInterrupted = false;
  }

  Future<void> setForceMixWithOthers(bool value, {bool? active}) async {
    await _enqueue(() async {
      await _initialized;
      // Android's audio_session recipe does not expose an equivalent of
      // AVAudioSessionCategoryOptions.mixWithOthers. Do not tear down and
      // recreate Android audio focus just to change an iOS-only preference.
      if (!Platform.isIOS) {
        if (active != null) {
          await session.setActive(active);
        }
        return;
      }
      if (_forceMixWithOthers == value) {
        if (active != null) {
          await session.setActive(active);
        }
        return;
      }
      _forceMixWithOthers = value;
      final controller = PlPlayerController.instance;
      final shouldActivate =
          active ??
          (controller?.hasPlaybackIntent ?? false);
      await session.setActive(false);
      await _configureSession();
      if (shouldActivate) {
        await session.setActive(true);
      }
    });
  }

  Future<void> _initSession() async {
    session = await AudioSession.instance;
    await _configureSession();

    session.interruptionEventStream.listen((event) {
      final player = PlPlayerController.instance;
      if (event.begin) {
        if (player == null || !player.hasPlaybackIntent) return;
        switch (event.type) {
          case AudioInterruptionType.duck:
            player.handleDuck(true);
            break;
          case AudioInterruptionType.pause:
            // 接收到其他 App 播放音频的通知，如果允许了同时播放，就无视
            // Android 仍使用独占 media AudioFocus，不能忽略焦点丢失，
            // 否则播放器会保持 playing 但实际没有音频输出。
            if (Platform.isIOS && mixWithOthers) return;
            _playInterrupted = true;
            unawaited(PlPlayerController.pauseIfExists(isInterrupt: true));
            break;
          case AudioInterruptionType.unknown:
            _playInterrupted = true;
            unawaited(PlPlayerController.pauseIfExists(isInterrupt: true));
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            player?.handleDuck(false);
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) {
              unawaited(PlPlayerController.playIfExists());
            }
            break;
          case AudioInterruptionType.unknown:
            if (_playInterrupted) {
              unawaited(PlPlayerController.playIfExists());
            }
            break;
        }
        _playInterrupted = false;
      }
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      PlPlayerController.pauseIfExists();
      // final player = PlPlayerController.getInstance();
      // if (player.playerStatus.playing) {
      //   player.pause();
      // }
    });
  }
}
