import 'package:PiliMax/pilimax/services/settings_transfer_service.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes the upstream two-section export', () {
    final payload = SettingsTransferService.normalize({
      'setting': {SettingBoxKey.mainTabBarView: true},
      'video': {'playSpeedDefault': 1.25},
    });

    expect(payload.report.source, SettingsTransferService.upstreamSource);
    expect(payload.setting[SettingBoxKey.mainTabBarView], isTrue);
    expect(payload.video['playSpeedDefault'], 1.25);
    expect(payload.localCache, isEmpty);
  });

  test('normalizes PiliNara legacy aliases and local cache', () {
    final payload = SettingsTransferService.normalize({
      'setting': {
        SettingBoxKey.appFontWeight: 4,
        SettingBoxKey.reply2SortType: 2,
        SettingBoxKey.appRcmd: true,
      },
      'video': const <String, dynamic>{},
      'localCache': {
        LocalCacheKey.blackMids: [1, 2],
        'notSupportedByPiliMax': true,
      },
    });

    expect(payload.report.source, SettingsTransferService.pilinaraSource);
    expect(
      payload.setting[SettingBoxKey.appFontWeightV2],
      4,
    );
    expect(
      payload.setting[SettingBoxKey.replyReplySortType],
      2,
    );
    expect(payload.setting[SettingBoxKey.rcmdMode], 0);
    expect(payload.localCache, containsPair(LocalCacheKey.blackMids, [1, 2]));
    expect(
      payload.report.skippedUnknownLocalCacheKeys,
      contains('notSupportedByPiliMax'),
    );
  });

  test(
    'exports a self-describing PiliMax payload with compatibility aliases',
    () {
      final exported = SettingsTransferService.buildExportMap(
        setting: {
          SettingBoxKey.appFontWeightV2: 5,
          SettingBoxKey.replyReplySortType: 1,
          SettingBoxKey.rcmdMode: 2,
          SettingBoxKey.aiApiKey: 'secret',
        },
        video: const <String, dynamic>{},
        localCache: const <String, dynamic>{},
      );
      final meta = exported['_meta'] as Map;
      final setting = exported['setting'] as Map;

      expect(meta['source'], SettingsTransferService.pilimaxSource);
      expect(meta['defaultSourceOrder'], [
        SettingsTransferService.upstreamSource,
        SettingsTransferService.pilinaraSource,
      ]);
      expect(setting[SettingBoxKey.appFontWeight], 5);
      expect(setting[SettingBoxKey.reply2SortType], 1);
      expect(setting[SettingBoxKey.appRcmd], isFalse);
      expect(setting.containsKey(SettingBoxKey.aiApiKey), isFalse);
    },
  );

  test('accepts a settings-only payload and preserves missing sections', () {
    final payload = SettingsTransferService.normalize({
      'settings': {SettingBoxKey.mainTabBarView: false},
    });

    expect(payload.setting[SettingBoxKey.mainTabBarView], isFalse);
    expect(payload.video, isEmpty);
    expect(payload.localCache, isEmpty);
  });
}
