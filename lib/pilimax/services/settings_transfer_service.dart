import 'package:PiliMax/utils/storage_key.dart';

final class SettingsImportReport {
  final String? source;
  final Set<String> migratedKeys = <String>{};
  final Set<String> skippedSensitiveKeys = <String>{};
  final Set<String> skippedUnknownLocalCacheKeys = <String>{};
  final Set<String> skippedInvalidFilterKeys = <String>{};

  SettingsImportReport({this.source});
}

final class SettingsTransferPayload {
  final Map<dynamic, dynamic> setting;
  final Map<dynamic, dynamic> video;
  final Map<String, dynamic> localCache;
  final SettingsImportReport report;

  const SettingsTransferPayload({
    required this.setting,
    required this.video,
    required this.localCache,
    required this.report,
  });
}

abstract final class SettingsTransferService {
  static const format = 'pili-settings';
  static const schemaVersion = 2;
  static const upstreamSource = 'PiliPlus';
  static const pilinaraSource = 'PiliNara';
  static const pilimaxSource = 'PiliMax';
  static const defaultSourceOrder = <String>[upstreamSource, pilinaraSource];
  static const settingSection = 'setting';
  static const videoSection = 'video';
  static const localCacheSection = 'localCache';

  static const sensitiveSettingKeys = <String>{
    SettingBoxKey.aiApiKey,
    SettingBoxKey.webdavPassword,
  };

  static const exportableLocalCacheKeys = <String>{
    LocalCacheKey.historyPause,
    LocalCacheKey.blackMids,
    LocalCacheKey.dynamicsBlockedMids,
    LocalCacheKey.whitelistMids,
    LocalCacheKey.recommendBlockedMids,
    LocalCacheKey.replyBlockedMids,
    LocalCacheKey.remarkMids,
    LocalCacheKey.danmakuFilterRules,
  };

  static Map<String, dynamic> buildExportMap({
    required Map<dynamic, dynamic> setting,
    required Map<dynamic, dynamic> video,
    required Map<String, dynamic> localCache,
    bool includeSensitive = false,
  }) {
    final settingValues = <String, dynamic>{};
    for (final entry in setting.entries) {
      if (entry.key is! String) {
        continue;
      }
      final key = entry.key as String;
      if (!includeSensitive && sensitiveSettingKeys.contains(key)) {
        continue;
      }
      settingValues[key] = entry.value;
    }
    _addCompatibilityAliases(settingValues);

    return {
      '_meta': {
        'format': format,
        'schemaVersion': schemaVersion,
        'source': pilimaxSource,
        'defaultSourceOrder': defaultSourceOrder,
      },
      settingSection: settingValues,
      videoSection: Map<String, dynamic>.fromEntries(
        video.entries
            .where((entry) => entry.key is String)
            .map((entry) => MapEntry(entry.key as String, entry.value)),
      ),
      localCacheSection: localCache,
    };
  }

  static SettingsTransferPayload normalize(Map<dynamic, dynamic> input) {
    final importedSetting = _readSection(input, settingSection, const [
      'settings',
    ]);
    final importedVideo = _readSection(input, videoSection, const ['videos']);
    if (importedSetting is! Map ||
        (importedVideo != null && importedVideo is! Map)) {
      throw const FormatException('设置文件格式无效');
    }

    final report = SettingsImportReport(source: _sourceOf(input));
    final setting = _normalizeSetting(importedSetting, report);
    final video = importedVideo is Map
        ? _normalizeMap(importedVideo, 'video')
        : <dynamic, dynamic>{};
    final localCache = <String, dynamic>{};
    final importedLocalCache = _readSection(input, localCacheSection, const [
      'local_cache',
    ]);
    if (importedLocalCache != null) {
      if (importedLocalCache is! Map) {
        throw const FormatException('设置文件格式无效');
      }
      for (final entry in importedLocalCache.entries) {
        if (entry.key is! String) {
          throw const FormatException('设置文件格式无效');
        }
        final key = entry.key as String;
        if (!exportableLocalCacheKeys.contains(key)) {
          report.skippedUnknownLocalCacheKeys.add(key);
          continue;
        }
        localCache[key] = entry.value;
      }
    }

    return SettingsTransferPayload(
      setting: setting,
      video: video,
      localCache: localCache,
      report: report,
    );
  }

  static dynamic _readSection(
    Map<dynamic, dynamic> input,
    String name,
    List<String> aliases,
  ) {
    if (input.containsKey(name)) {
      return input[name];
    }
    for (final alias in aliases) {
      if (input.containsKey(alias)) {
        return input[alias];
      }
    }
    return null;
  }

  static String? _sourceOf(Map<dynamic, dynamic> input) {
    final meta = input['_meta'];
    if (meta is Map && meta['source'] is String) {
      return meta['source'] as String;
    }
    if (input.containsKey(localCacheSection) ||
        input.containsKey('local_cache')) {
      return pilinaraSource;
    }
    return upstreamSource;
  }

  static Map<dynamic, dynamic> _normalizeSetting(
    Map<dynamic, dynamic> source,
    SettingsImportReport report,
  ) {
    final values = _normalizeMap(source, 'setting');
    for (final key in sensitiveSettingKeys) {
      if (values.containsKey(key)) {
        values.remove(key);
        report.skippedSensitiveKeys.add(key);
      }
    }

    _copyAlias(
      values,
      canonical: SettingBoxKey.appFontWeightV2,
      legacy: SettingBoxKey.appFontWeight,
      report: report,
    );
    _copyAlias(
      values,
      canonical: SettingBoxKey.replyReplySortType,
      legacy: SettingBoxKey.reply2SortType,
      report: report,
    );
    if (!values.containsKey(SettingBoxKey.rcmdMode) &&
        values[SettingBoxKey.appRcmd] is bool) {
      values[SettingBoxKey.rcmdMode] = values[SettingBoxKey.appRcmd] == true
          ? 0
          : 1;
      report.migratedKeys.add(
        '${SettingBoxKey.appRcmd}->${SettingBoxKey.rcmdMode}',
      );
    }

    values
      ..remove(SettingBoxKey.appFontWeight)
      ..remove(SettingBoxKey.reply2SortType)
      ..remove(SettingBoxKey.appRcmd);
    return values;
  }

  static Map<dynamic, dynamic> _normalizeMap(
    Map<dynamic, dynamic> source,
    String section,
  ) {
    final values = <dynamic, dynamic>{};
    for (final entry in source.entries) {
      if (entry.key is! String) {
        throw FormatException('$section 设置键无效');
      }
      values[entry.key] = entry.value;
    }
    return values;
  }

  static void _copyAlias(
    Map<dynamic, dynamic> values, {
    required String canonical,
    required String legacy,
    required SettingsImportReport report,
  }) {
    if (!values.containsKey(canonical) && values.containsKey(legacy)) {
      values[canonical] = values[legacy];
      report.migratedKeys.add('$legacy->$canonical');
    }
  }

  static void _addCompatibilityAliases(Map<String, dynamic> values) {
    final fontWeight = values[SettingBoxKey.appFontWeightV2];
    if (fontWeight != null &&
        !values.containsKey(SettingBoxKey.appFontWeight)) {
      values[SettingBoxKey.appFontWeight] = fontWeight;
    }

    final replySort = values[SettingBoxKey.replyReplySortType];
    if (replySort != null &&
        !values.containsKey(SettingBoxKey.reply2SortType)) {
      values[SettingBoxKey.reply2SortType] = replySort;
    }

    final rcmdMode = values[SettingBoxKey.rcmdMode];
    if (rcmdMode is int && !values.containsKey(SettingBoxKey.appRcmd)) {
      // The legacy boolean cannot represent the merged mode; app/web is the
      // closest compatible representation for older PiliPlus builds. Treat
      // merged mode as web so it does not silently enable app-only requests.
      values[SettingBoxKey.appRcmd] = rcmdMode == 0;
    }
  }
}
