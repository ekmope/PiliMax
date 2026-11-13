import 'dart:io';

import 'package:PiliMax/models_new/live/live_room_info_h5/data.dart';
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/services/audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<dynamic> settings;
  late VideoPlayerServiceHandler handler;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pilimax-audio-state-');
    Hive.init(directory.path);
    settings = await Hive.openBox<dynamic>('setting');
    GStorage.setting = settings;
  });
  tearDownAll(() async {
    await settings.close();
    await directory.delete(recursive: true);
  });
  setUp(() {
    handler = VideoPlayerServiceHandler()..enableBackgroundPlay = true;
  });
  tearDown(() => handler.forceClear());

  test('live advertises no seek and ignores a direct system seek', () async {
    handler
      ..onVideoDetailChange(RoomInfoH5Data(), 1, 'live')
      ..onStatusChange(PlayerStatus.playing, false, true);
    var sought = false;
    handler.onSeek = (_) async {
      sought = true;
    };
    expect(
      handler.playbackState.value.systemActions,
      isNot(contains(MediaAction.seek)),
    );
    final oldPosition = handler.playbackState.value.updatePosition;
    await handler.seek(const Duration(seconds: 30));
    expect(sought, isFalse);
    expect(handler.playbackState.value.updatePosition, oldPosition);
  });

  test(
    'video retains seek callbacks and reports actual playback speed',
    () async {
      handler
        ..onVideoDetailChange(
          Part(cid: 2, duration: 120, part: '视频'),
          2,
          'video',
        )
        ..onStatusChange(PlayerStatus.paused, false, false);
      Duration? sought;
      handler.onSeek = (position) async {
        sought = position;
      };
      expect(
        handler.playbackState.value.systemActions,
        contains(MediaAction.seek),
      );
      handler.onPositionChange(const Duration(seconds: 10), speed: 1.5);
      expect(handler.playbackState.value.speed, 1.5);
      handler.onSpeedChange(2);
      expect(handler.playbackState.value.speed, 2);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 10),
      );
      await handler.seek(const Duration(seconds: 30));
      expect(sought, const Duration(seconds: 30));
      handler
        ..onSpeedChange(double.nan)
        ..onPositionChange(const Duration(seconds: 31));
      expect(handler.playbackState.value.speed, 2);
    },
  );

  test('cleared sessions cannot dispatch a stale seek callback', () async {
    handler.onVideoDetailChange(Part(cid: 3, duration: 60), 3, 'old-video');
    var sought = false;
    handler
      ..onSeek = (_) async {
        sought = true;
      }
      ..forceClear();
    await handler.seek(const Duration(seconds: 5));
    expect(sought, isFalse);
    expect(handler.playbackState.value.systemActions, isEmpty);
  });
}
