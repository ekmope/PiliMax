import 'package:PiliMax/grpc/bilibili/app/playurl/v1.pb.dart' as app;
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/pilimax/services/playback/trial_play_view_merger.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges URL-backed known codecs and preserves Web audio', () {
    final audio = AudioItem()
      ..id = 30280
      ..baseUrl = 'https://web.example/audio.m4s';
    final target = _target(audio: audio);
    final reply = _reply(
      sources: const [
        (7, 'https://app.example/avc.m4s'),
        (12, 'https://app.example/hevc.m4s'),
        (13, 'https://app.example/av1.m4s'),
        (20, 'https://app.example/dolby.m4s'),
      ],
      appAudioUrl: 'https://app.example/audio.m4s',
    );

    final result = TrialPlayViewMerger.merge(
      target: target,
      reply: reply,
      unlimitedTrialEnabled: true,
    );

    expect(result.durationMismatch, isFalse);
    expect(result.playableQualityIds, {VideoQuality.super4K.code});
    expect(
      target.dash!.video!
          .where((item) => item.isPreview)
          .map(
            (item) => item.codecs,
          ),
      containsAll(<String>['avc1', 'hev1', 'av01', 'dvh1']),
    );
    expect(target.dash!.audio, hasLength(1));
    expect(identical(target.dash!.audio!.single, audio), isTrue);
    expect(target.dash!.audio!.single.baseUrl, startsWith('https://web.'));
    expect(
      target.supportFormats!.single.codecs,
      containsAll(<String>['avc1', 'hev1', 'av01', 'dvh1']),
    );
  });

  test('rejects a clear App/Web duration mismatch without mutation', () {
    final audio = AudioItem()..baseUrl = 'https://web.example/audio.m4s';
    final target = _target(audio: audio, durationMs: 120000);
    final originalVideos = List<VideoItem>.of(target.dash!.video!);
    final reply = _reply(
      durationMs: 100000,
      sources: const [(7, 'https://app.example/video.m4s')],
    );

    final result = TrialPlayViewMerger.merge(
      target: target,
      reply: reply,
      unlimitedTrialEnabled: true,
    );

    expect(result.durationMismatch, isTrue);
    expect(result.playableQualityIds, isEmpty);
    expect(target.dash!.video, orderedEquals(originalVideos));
    expect(identical(target.dash!.audio!.single, audio), isTrue);
  });

  test('allows small duration rounding differences', () {
    final target = _target(durationMs: 100000);
    final result = TrialPlayViewMerger.merge(
      target: target,
      reply: _reply(
        durationMs: 104999,
        sources: const [(7, 'https://app.example/video.m4s')],
      ),
      unlimitedTrialEnabled: true,
    );

    expect(result.durationMismatch, isFalse);
    expect(result.playableQualityIds, {VideoQuality.super4K.code});
  });

  test('unlimited mode ignores exhausted times but keeps other gates', () {
    final reply = _reply(
      times: 0,
      sources: const [(7, 'https://app.example/video.m4s')],
    );

    final enabled = TrialPlayViewMerger.merge(
      target: _target(),
      reply: reply,
      unlimitedTrialEnabled: true,
    );
    final disabled = TrialPlayViewMerger.merge(
      target: _target(),
      reply: reply,
      unlimitedTrialEnabled: false,
    );

    expect(enabled.playableQualityIds, {VideoQuality.super4K.code});
    expect(disabled.playableQualityIds, isEmpty);
  });

  test('rejects empty, unknown, DRM, errored and forbidden streams', () {
    for (final reply in <app.PlayViewReply>[
      _reply(sources: const [(7, '')]),
      _reply(sources: const [(999, 'https://app.example/video.m4s')]),
      _reply(
        sources: const [(7, 'https://app.example/video.m4s')],
        supportDrm: true,
      ),
      _reply(
        sources: const [(7, 'https://app.example/video.m4s')],
        error: app.PlayErr.WithMultiDeviceLoginErr,
      ),
      _reply(
        sources: const [(7, 'https://app.example/video.m4s')],
        canWatch: false,
      ),
    ]) {
      final target = _target();
      final result = TrialPlayViewMerger.merge(
        target: target,
        reply: reply,
        unlimitedTrialEnabled: true,
      );
      expect(result.playableQualityIds, isEmpty);
      expect(target.dash!.video!.where((item) => item.isPreview), isEmpty);
    }
  });

  test('keeps an existing URL-backed Web quality authoritative', () {
    final target = _target(
      webVideo: VideoItem(
        id: VideoQuality.super4K.code,
        baseUrl: 'https://web.example/video.m4s',
        codecs: 'avc1',
        quality: VideoQuality.super4K,
      ),
    );

    final result = TrialPlayViewMerger.merge(
      target: target,
      reply: _reply(
        sources: const [(13, 'https://app.example/video.m4s')],
      ),
      unlimitedTrialEnabled: true,
    );

    expect(result.playableQualityIds, isEmpty);
    expect(target.dash!.video, hasLength(2));
    expect(target.dash!.video!.where((item) => item.isPreview), isEmpty);
    expect(
      target.dash!.video!.where(
        (item) => item.quality == VideoQuality.super4K,
      ),
      hasLength(1),
    );
  });

  test('replaces metadata-only codecs with URL-backed App codecs', () {
    final target = _target();
    target.supportFormats!.add(
      FormatItem(
        quality: VideoQuality.super4K.code,
        codecs: <String>['avc1', 'hev1'],
      ),
    );

    TrialPlayViewMerger.merge(
      target: target,
      reply: _reply(
        sources: const [(13, 'https://app.example/video.m4s')],
      ),
      unlimitedTrialEnabled: true,
    );

    expect(
      target.supportFormats!
          .singleWhere((item) => item.quality == VideoQuality.super4K.code)
          .codecs,
      <String>['av01'],
    );
  });

  test('keeps codecs from separate streams and ignores an empty tail', () {
    final target = _target();

    TrialPlayViewMerger.merge(
      target: target,
      reply: _reply(
        sources: const [
          (7, 'https://app.example/avc.m4s'),
          (13, 'https://app.example/av1.m4s'),
          (12, ''),
        ],
      ),
      unlimitedTrialEnabled: true,
    );

    expect(
      target.supportFormats!.single.codecs,
      containsAllInOrder(<String>['avc1', 'av01']),
    );
  });
}

PlayUrlModel _target({
  int durationMs = 100000,
  AudioItem? audio,
  VideoItem? webVideo,
}) => PlayUrlModel(
  timeLength: durationMs,
  acceptQuality: <int>[VideoQuality.high1080.code],
  dash: Dash(
    video: <VideoItem>[
      ?webVideo,
      VideoItem(
        id: VideoQuality.high1080.code,
        baseUrl: 'https://web.example/1080.m4s',
        codecs: 'avc1',
        quality: VideoQuality.high1080,
      ),
    ],
    audio: audio == null ? null : <AudioItem>[audio],
  ),
  supportFormats: <FormatItem>[],
);

app.PlayViewReply _reply({
  int durationMs = 100000,
  required List<(int, String)> sources,
  String? appAudioUrl,
  bool supportDrm = false,
  app.PlayErr error = app.PlayErr.NoErr,
  bool canWatch = true,
  int times = 1,
}) => app.PlayViewReply(
  ab: app.AB(
    glance: app.Glance(canWatch: canWatch, times: Int64(times)),
  ),
  videoInfo: app.VideoInfo(
    timelength: Int64(durationMs),
    dashAudio: appAudioUrl == null
        ? const <app.DashItem>[]
        : <app.DashItem>[
            app.DashItem(id: 30280, baseUrl: appAudioUrl, codecid: 0),
          ],
    streamList: <app.Stream>[
      for (final (codec, url) in sources)
        app.Stream(
          streamInfo: app.StreamInfo(
            quality: VideoQuality.super4K.code,
            hasPreview: true,
            supportDrm: supportDrm,
            errCode: error,
          ),
          dashVideo: app.DashVideo(
            baseUrl: url,
            codecid: codec,
            width: 3840,
            height: 2160,
            frameRate: '60',
          ),
        ),
    ],
  ),
);
