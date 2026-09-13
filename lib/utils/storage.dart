import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models/user/danmaku_rule_adapter.dart';
import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account_adapter.dart';
import 'package:PiliPlus/utils/accounts/account_type_adapter.dart';
import 'package:PiliPlus/utils/accounts/cookie_jar_adapter.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/set_int_adapter.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;

abstract final class GStorage {
  static late final Box<UserInfoData> userInfo;
  static late final Box<dynamic> historyWord;
  static late final Box<dynamic> localCache;
  static late final Box<dynamic> setting;
  static late final Box<dynamic> video;
  static late final Box<int> watchProgress;
  static const exportableLocalCacheKeys = [
    'historyPause',
    'blackMids',
    'dynamicsBlockedMids',
    'whitelistMids',
    'recommendBlockedMids',
    'replyBlockedMids',
    'remarkMids',
  ];
  static late final Box<Uint8List>? reply;

  static File get trafficStatsFile =>
      File(path.join(appSupportDirPath, 'traffic_stats.json'));

  static File get cdnDiagnosticsFile =>
      File(path.join(appSupportDirPath, 'cdn_diagnostic_latest.json'));

  static File get cdnDiagnosticsHistoryFile =>
      File(path.join(appSupportDirPath, 'cdn_diagnostic_history_v3.jsonl'));

  static Map<String, dynamic>? readJsonMapSync(File file) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> writeJsonFile(File file, Object? value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value), flush: true);
  }

  static Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  static List<({String id, Map<String, dynamic> record})>
  readCdnDiagnosticsSync() {
    if (!cdnDiagnosticsFile.existsSync()) return const [];
    // 最新结果快照本就极小；过大的文件是历史遗留的逐块记录，绝不同步解码。
    if (cdnDiagnosticsFile.lengthSync() > 1 << 23) {
      unawaited(_deleteFileIfExists(cdnDiagnosticsFile));
      return const [];
    }
    final result = <({String id, Map<String, dynamic> record})>[];
    try {
      final decoded = jsonDecode(cdnDiagnosticsFile.readAsStringSync());
      if (decoded is! Map || decoded['schemaVersion'] != 3) {
        unawaited(_deleteFileIfExists(cdnDiagnosticsFile));
        return const [];
      }
      for (final raw in (decoded['records'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final record = raw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final id =
            '${record['testRunStartedAtUs']}:'
            '${record['cdn'] is Map ? (record['cdn'] as Map)['index'] : result.length}';
        result.add((id: id, record: record));
      }
    } catch (_) {
      unawaited(_deleteFileIfExists(cdnDiagnosticsFile));
    }
    return result;
  }

  static Future<void> replaceCdnDiagnostics(
    List<({String id, Map<String, dynamic> record})> entries,
  ) async {
    if (entries.isEmpty) {
      await _deleteFileIfExists(cdnDiagnosticsFile);
      return;
    }
    var latestRun = 0;
    for (final entry in entries) {
      final record = entry.record;
      final run =
          (record['testRunStartedAtUs'] as num?)?.toInt() ??
          (record['recordedAtUs'] as num?)?.toInt() ??
          0;
      if (run > latestRun) latestRun = run;
    }
    final latest = [
      for (final entry in entries)
        if (((entry.record['testRunStartedAtUs'] as num?)?.toInt() ??
                    (entry.record['recordedAtUs'] as num?)?.toInt() ??
                    0) ==
                latestRun)
          entry.record,
    ];
    await cdnDiagnosticsFile.parent.create(recursive: true);
    final temp = File('${cdnDiagnosticsFile.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'schemaVersion': 3, 'records': latest}),
      flush: true,
    );
    if (await cdnDiagnosticsFile.exists()) await cdnDiagnosticsFile.delete();
    await temp.rename(cdnDiagnosticsFile.path);
  }

  static List<({String id, Map<String, dynamic> record})>
  readCdnDiagnosticsHistorySync() {
    if (!cdnDiagnosticsHistoryFile.existsSync()) return const [];
    final result = <({String id, Map<String, dynamic> record})>[];
    try {
      for (final line in cdnDiagnosticsHistoryFile.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! Map || decoded['schemaVersion'] != 3) {
          throw const FormatException('unsupported CDN history schema');
        }
        for (final raw in (decoded['records'] as List? ?? const [])) {
          if (raw is! Map) continue;
          final record = raw.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final id =
              '${record['testRunStartedAtUs']}:'
              '${record['cdn'] is Map ? (record['cdn'] as Map)['index'] : result.length}';
          result.add((id: id, record: record));
        }
      }
    } catch (_) {
      unawaited(_deleteFileIfExists(cdnDiagnosticsHistoryFile));
      return const [];
    }
    return result;
  }

  static Future<void> appendCdnDiagnosticsHistory(
    List<({String id, Map<String, dynamic> record})> entries,
  ) async {
    if (entries.isEmpty) return;
    await cdnDiagnosticsHistoryFile.parent.create(recursive: true);
    await cdnDiagnosticsHistoryFile.writeAsString(
      '${jsonEncode({
        'schemaVersion': 3,
        'records': [for (final entry in entries) entry.record],
      })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<void> replaceCdnDiagnosticsHistory(
    List<({String id, Map<String, dynamic> record})> entries,
  ) async {
    if (entries.isEmpty) {
      await _deleteFileIfExists(cdnDiagnosticsHistoryFile);
      return;
    }

    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final entry in entries) {
      final record = entry.record;
      final run =
          (record['testRunStartedAtUs'] as num?)?.toInt() ??
          (record['recordedAtUs'] as num?)?.toInt() ??
          0;
      (grouped[run] ??= []).add(record);
    }

    final runs = grouped.keys.toList()..sort();
    await cdnDiagnosticsHistoryFile.parent.create(recursive: true);
    final temp = File('${cdnDiagnosticsHistoryFile.path}.tmp');
    final sink = temp.openWrite();
    try {
      for (final run in runs) {
        sink.writeln(jsonEncode({'schemaVersion': 3, 'records': grouped[run]}));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (await cdnDiagnosticsHistoryFile.exists()) {
      await cdnDiagnosticsHistoryFile.delete();
    }
    await temp.rename(cdnDiagnosticsHistoryFile.path);
  }

  static Future<void> init() async {
    Hive.init(path.join(appSupportDirPath, 'hive'));
    regAdapter();

    await Future.wait([
      // 登录用户信息
      Hive.openBox<UserInfoData>(
        'userInfo',
        compactionStrategy: (int entries, int deletedEntries) {
          return deletedEntries > 2;
        },
      ).then((res) => userInfo = res),
      // 本地缓存
      Hive.openBox(
        'localCache',
        compactionStrategy: (int entries, int deletedEntries) {
          return deletedEntries > 4;
        },
      ).then((res) => localCache = res),
      // 设置
      Hive.openBox('setting').then((res) => setting = res),
      // 搜索历史
      Hive.openBox(
        'historyWord',
        compactionStrategy: (int entries, int deletedEntries) {
          return deletedEntries > 10;
        },
      ).then((res) => historyWord = res),
      // 视频设置
      Hive.openBox('video').then((res) => video = res),
      Accounts.init(),
      Hive.openBox<int>(
        'watchProgress',
        keyComparator: _intStrDescKeyComparator,
        compactionStrategy: (entries, deletedEntries) {
          return deletedEntries > 4;
        },
      ).then((res) => watchProgress = res),
    ]);

    if (Pref.saveReply) {
      reply = await Hive.openBox<Uint8List>(
        'reply',
        keyComparator: _intStrDescKeyComparator,
        compactionStrategy: (entries, deletedEntries) {
          return deletedEntries > 10;
        },
      );
    } else {
      reply = null;
    }
  }

  static String exportAllSettings() {
    // 导出需要保存的 localCache 数据，排除临时数据
    final localCacheData = <String, dynamic>{};
    for (final key in exportableLocalCacheKeys) {
      final value = localCache.get(key);
      if (value != null) {
        localCacheData[key] = _encodeLocalCacheValue(key, value);
      }
    }

    return Utils.jsonEncoder.convert({
      setting.name: setting.toMap(),
      video.name: video.toMap(),
      localCache.name: localCacheData,
    });
  }

  static Future<void> importAllSettings(String data) =>
      importAllJsonSettings(jsonDecode(data));

  static Future<List<void>> importAllJsonSettings(
    Map<String, dynamic> map,
  ) {
    final futures = <Future<void>>[
      setting.clear().then((_) => setting.putAll(map[setting.name])),
      video.clear().then((_) => video.putAll(map[video.name])),
    ];

    // 导入 localCache 数据（如果存在）
    if (map.containsKey(localCache.name)) {
      final localCacheMap = map[localCache.name] as Map<String, dynamic>;
      for (final entry in localCacheMap.entries) {
        if (!exportableLocalCacheKeys.contains(entry.key)) {
          continue;
        }
        futures.add(
          localCache.put(
            entry.key,
            _decodeLocalCacheValue(entry.key, entry.value),
          ),
        );
      }
    }

    return Future.wait(futures);
  }

  static void regAdapter() {
    Hive
      ..registerAdapter(OwnerAdapter())
      ..registerAdapter(UserInfoDataAdapter())
      ..registerAdapter(LevelInfoAdapter())
      ..registerAdapter(BiliCookieJarAdapter())
      ..registerAdapter(LoginAccountAdapter())
      ..registerAdapter(AccountTypeAdapter())
      ..registerAdapter(SetIntAdapter())
      ..registerAdapter(RuleFilterAdapter());
  }

  static dynamic _encodeLocalCacheValue(String key, dynamic value) {
    return switch (key) {
      'blackMids' ||
      'dynamicsBlockedMids' => value is Set ? value.toList() : value,
      'whitelistMids' ||
      'recommendBlockedMids' ||
      'replyBlockedMids' ||
      'remarkMids' =>
        value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : value,
      _ => value,
    };
  }

  static dynamic _decodeLocalCacheValue(String key, dynamic value) {
    return switch (key) {
      'blackMids' || 'dynamicsBlockedMids' =>
        value is List ? value.whereType<int>().toSet() : value,
      'whitelistMids' ||
      'recommendBlockedMids' ||
      'replyBlockedMids' ||
      'remarkMids' =>
        value is Map
            ? value.map(
                (k, v) =>
                    MapEntry(k.toString(), v is String ? v : v.toString()),
              )
            : value,
      _ => value,
    };
  }

  static Future<List<void>> compact() {
    return Future.wait([
      userInfo.compact(),
      historyWord.compact(),
      localCache.compact(),
      setting.compact(),
      video.compact(),
      Accounts.account.compact(),
      watchProgress.compact(),
      ?reply?.compact(),
    ]);
  }

  static Future<List<void>> close() {
    return Future.wait([
      userInfo.close(),
      historyWord.close(),
      localCache.close(),
      setting.close(),
      video.close(),
      Accounts.account.close(),
      watchProgress.close(),
      ?reply?.close(),
    ]);
  }

  static Future<List<void>> clear() {
    return Future.wait([
      userInfo.clear(),
      historyWord.clear(),
      localCache.clear(),
      setting.clear(),
      video.clear(),
      Accounts.clear(),
      watchProgress.clear(),
      ?reply?.clear(),
    ]);
  }

  static int _intStrDescKeyComparator(dynamic k1, dynamic k2) {
    if (k1 is int) {
      if (k2 is int) {
        return k2.compareTo(k1);
      } else {
        return -1;
      }
    } else if (k2 is String) {
      final lenCompare = k2.length.compareTo((k1 as String).length);
      if (lenCompare == 0) {
        return k2.compareTo(k1);
      } else {
        return lenCompare;
      }
    } else {
      return 1;
    }
  }
}
