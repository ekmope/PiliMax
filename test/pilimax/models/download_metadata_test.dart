import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/models_new/sponsor_block/segment_item.dart';
import 'package:PiliMax/pilimax/models_new/download/playback_meta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'old downloads load without volume and preserve folder customization',
    () {
      final entry = _entry();
      final json = entry.toJson()..remove('volume');
      final restored = BiliDownloadEntryInfo.fromJson(json);
      expect(restored.volume, isNull);
      expect(restored.autoFolderTitle, '我的合集');
      expect(restored.autoFolderSourceKey, 'ugc-season:5');
      expect(restored.autoFolderIndex, 7);
      expect(restored.ownerId, 42);

      restored
        ..volume = Volume.fromCache(_volumeJson)
        ..seasonInfo = const SeasonInfo(
          index: 9,
          id: 5,
          title: '新的合集信息',
          cover: '',
          mid: 42,
          uname: 'UP',
        );
      final updated = BiliDownloadEntryInfo.fromJson(restored.toJson());
      expect(updated.volume!.measuredI, -18);
      expect(updated.seasonInfo!.index, 9);
      expect(updated.autoFolderTitle, entry.autoFolderTitle);
      expect(updated.autoFolderSourceKey, entry.autoFolderSourceKey);
      expect(updated.autoFolderIndex, entry.autoFolderIndex);
    },
  );

  test('cached volume rejects malformed and non-finite values', () {
    for (final value in [
      null,
      [],
      'bad',
      <String, dynamic>{},
      {..._volumeJson, 'measured_i': 'bad'},
      {..._volumeJson, 'measured_tp': double.infinity},
    ]) {
      expect(Volume.fromCache(value), isNull);
    }
    final volume = Volume.fromCache({
      ..._volumeJson,
      'future_metadata': {'key': 'value'},
    })!;
    expect(Volume.fromCache(volume.toJson())!.toJson(), _volumeJson);
    expect(volume.format({'tp': 5}), contains('TP=-9.0'));
  });

  test('refreshing one offline skip source preserves the other sources', () {
    const chapters = DownloadPlaybackChapters(
      fetchedAt: 1,
      items: [
        DownloadPlaybackChapter(fromMs: 1000, toMs: 2000, content: '章节'),
      ],
    );
    final initial = const DownloadPlaybackMeta(chapters: chapters)
        .withSkipSegments(
          fetchedAt: 2,
          sponsorBlock: [_segment('sponsor', 'sb-old')],
          clipInfo: [_segment('intro', 'pgc-old')],
        );
    final pgcUpdated = initial.withSkipSegments(
      fetchedAt: 3,
      clipInfo: [_segment('outro', 'pgc-new')],
    );
    expect(identical(pgcUpdated.chapters, chapters), isTrue);
    expect(pgcUpdated.sponsorBlock!.items.single.uuid, 'sb-old');
    expect(pgcUpdated.clipInfo!.items.single.uuid, 'pgc-new');

    // An explicit empty response clears only that source; null leaves it alone.
    final sbCleared = pgcUpdated.withSkipSegments(
      fetchedAt: 4,
      sponsorBlock: const [],
    );
    final restored = DownloadPlaybackMeta.fromJson(sbCleared.toJson());
    expect(restored.sponsorBlock!.items, isEmpty);
    expect(restored.clipInfo!.items.single.uuid, 'pgc-new');
    expect(restored.chapters!.items.single.content, '章节');
  });
}

const _volumeJson = <String, dynamic>{
  'measured_i': -18,
  'measured_lra': 8,
  'measured_tp': -12,
  'measured_threshold': -28,
  'target_offset': 1,
  'target_i': -16,
  'target_tp': -1,
};

SegmentItemModel _segment(String category, String uuid) => SegmentItemModel(
  category: category,
  uuid: uuid,
  segment: const [0, 1000],
);

BiliDownloadEntryInfo _entry() => BiliDownloadEntryInfo(
  isCompleted: true,
  totalBytes: 100,
  downloadedBytes: 100,
  title: '视频',
  cover: '',
  typeTag: '80',
  preferedVideoQuality: 80,
  guessedTotalBytes: 100,
  totalTimeMilli: 1000,
  danmakuCount: 0,
  avid: 1,
  bvid: 'BV1',
  ownerId: 42,
  ownerName: 'UP',
  autoFolderTitle: '我的合集',
  autoFolderSourceKey: 'ugc-season:5',
  autoFolderIndex: 7,
);
