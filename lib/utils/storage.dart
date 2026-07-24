import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliMax/models/model_owner.dart';
import 'package:PiliMax/models/user/danmaku_rule.dart';
import 'package:PiliMax/models/user/danmaku_rule_adapter.dart';
import 'package:PiliMax/models/user/info.dart';
import 'package:PiliMax/utils/android/android_mmkv_box.dart';
import 'package:PiliMax/utils/android/android_mmkv_storage_codec.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/account_adapter.dart';
import 'package:PiliMax/utils/accounts/account_type_adapter.dart';
import 'package:PiliMax/utils/accounts/cookie_jar_adapter.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:PiliMax/utils/set_int_adapter.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/storage/reply_cache_store.dart';
import 'package:PiliMax/utils/storage/watch_progress_store.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;

abstract final class GStorage {
  static late final Box<UserInfoData> userInfo;
  static late final Box<dynamic> historyWord;
  static late final Box<dynamic> localCache;
  static late final Box<dynamic> setting;
  static late final Box<dynamic> video;
  static late final Box<String> _androidMmkvMigrationState;
  static late final Box<int> watchProgress;
  static late final WatchProgressStore watchProgressStore;
  static const exportableLocalCacheKeys = [
    'historyPause',
    'blackMids',
    'dynamicsBlockedMids',
    'whitelistMids',
    'recommendBlockedMids',
    'replyBlockedMids',
    'danmakuFilterRules',
  ];
  static late final Box<Uint8List>? reply;
  static late final ReplyCacheStore replyCacheStore;

  static Future<void> init() async {
    Hive.init(path.join(appSupportDirPath, 'hive'));
    regAdapter();
    _androidMmkvMigrationState = await Hive.openBox<String>(
      'androidMmkvMigrationState',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 4,
    );
    final migrationState = HiveAndroidMmkvMigrationState(
      _androidMmkvMigrationState,
    );

    await Future.wait([
      // 登录用户信息
      openAndroidMmkvBackedBox<UserInfoData>(
        name: 'userInfo',
        valueEncoder: AndroidMmkvStorageCodec.encodeUserInfoData,
        valueDecoder: AndroidMmkvStorageCodec.decodeUserInfoData,
        migrationState: migrationState,
        openHive: () => Hive.openBox<UserInfoData>(
          'userInfo',
          compactionStrategy: (int entries, int deletedEntries) {
            return deletedEntries > 2;
          },
        ),
      ).then((res) => userInfo = res),
      // 本地缓存
      openAndroidMmkvBackedBox<dynamic>(
        name: 'localCache',
        valueEncoder: AndroidMmkvStorageCodec.encodeLocalCacheValue,
        valueDecoder: AndroidMmkvStorageCodec.decodeLocalCacheValue,
        migrationState: migrationState,
        openHive: () => Hive.openBox(
          'localCache',
          compactionStrategy: (int entries, int deletedEntries) {
            return deletedEntries > 4;
          },
        ),
      ).then((res) => localCache = res),
      // 设置
      openAndroidMmkvBackedBox<dynamic>(
        name: 'setting',
        migrationState: migrationState,
        openHive: () => Hive.openBox('setting'),
      ).then((res) => setting = res),
      // 搜索历史
      openAndroidMmkvBackedBox<dynamic>(
        name: 'historyWord',
        migrationState: migrationState,
        openHive: () => Hive.openBox(
          'historyWord',
          compactionStrategy: (int entries, int deletedEntries) {
            return deletedEntries > 10;
          },
        ),
      ).then((res) => historyWord = res),
      // 视频设置
      openAndroidMmkvBackedBox<dynamic>(
        name: 'video',
        migrationState: migrationState,
        openHive: () => Hive.openBox('video'),
      ).then((res) => video = res),
      Accounts.init(),
    ]);

    watchProgress = await openAndroidMmkvBackedBox<int>(
      name: 'watchProgress',
      migrationState: migrationState,
      keyComparator: _intStrDescKeyComparator,
      loadMode: AndroidMmkvLoadMode.lazy,
      openHive: () => Hive.openBox<int>(
        'watchProgress',
        keyComparator: _intStrDescKeyComparator,
        compactionStrategy: (entries, deletedEntries) {
          return deletedEntries > 4;
        },
      ),
    );
    watchProgressStore = WatchProgressStore(
      watchProgress,
      orderStore: localCache,
    );
    await watchProgressStore.enforceLimit();

    if (Pref.saveReply) {
      reply = await openAndroidMmkvBackedBox<Uint8List>(
        name: 'reply',
        migrationState: migrationState,
        keyComparator: _intStrDescKeyComparator,
        loadMode: AndroidMmkvLoadMode.lazy,
        openHive: () => Hive.openBox<Uint8List>(
          'reply',
          keyComparator: _intStrDescKeyComparator,
          compactionStrategy: (entries, deletedEntries) {
            return deletedEntries > 10;
          },
        ),
      );
    } else {
      reply = null;
    }
    replyCacheStore = ReplyCacheStore(reply, orderStore: localCache);
    await replyCacheStore.enforceLimit();
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
      'whitelistMids' || 'recommendBlockedMids' || 'replyBlockedMids' =>
        value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : value,
      'danmakuFilterRules' =>
        value is RuleFilter
            ? {
                'dmFilterString': value.dmFilterString,
                'dmRegExp': value.dmRegExp.map((e) => e.pattern).toList(),
                'dmUid': value.dmUid.toList(),
              }
            : value,
      _ => value,
    };
  }

  static dynamic _decodeLocalCacheValue(String key, dynamic value) {
    return switch (key) {
      'blackMids' || 'dynamicsBlockedMids' =>
        value is List ? value.whereType<int>().toSet() : value,
      'whitelistMids' || 'recommendBlockedMids' || 'replyBlockedMids' =>
        value is Map
            ? value.map(
                (k, v) =>
                    MapEntry(k.toString(), v is String ? v : v.toString()),
              )
            : value,
      'danmakuFilterRules' =>
        value is Map
            ? RuleFilter(
                (value['dmFilterString'] as List? ?? const [])
                    .whereType<String>()
                    .toList(),
                (value['dmRegExp'] as List? ?? const [])
                    .whereType<String>()
                    .map((e) => RegExp(e, caseSensitive: false))
                    .toList(),
                (value['dmUid'] as List? ?? const [])
                    .whereType<String>()
                    .toSet(),
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
      _androidMmkvMigrationState.compact(),
      watchProgress.compact(),
      ?reply?.compact(),
    ]);
  }

  static Future<List<void>> close() async {
    await Future.wait([
      watchProgressStore.beginClose(),
      replyCacheStore.beginClose(),
    ]);
    return Future.wait([
      userInfo.close(),
      historyWord.close(),
      localCache.close(),
      setting.close(),
      video.close(),
      Accounts.account.close(),
      _androidMmkvMigrationState.close(),
      watchProgress.close(),
      ?reply?.close(),
    ]);
  }

  static Future<List<void>> clear() async {
    await Future.wait([
      watchProgressStore.clear(),
      replyCacheStore.clear(),
    ]);
    return Future.wait([
      userInfo.clear(),
      historyWord.clear(),
      localCache.clear(),
      setting.clear(),
      video.clear(),
      Accounts.clear(),
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
