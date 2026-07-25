import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/models/model_owner.dart';
import 'package:PiliMax/models/user/danmaku_rule.dart';
import 'package:PiliMax/models/user/danmaku_rule_adapter.dart';
import 'package:PiliMax/models/user/info.dart';
import 'package:PiliMax/utils/android/android_mmkv_box.dart';
import 'package:PiliMax/utils/android/android_mmkv_recovery.dart';
import 'package:PiliMax/utils/android/android_mmkv_storage_codec.dart';
import 'package:PiliMax/utils/cache_policy.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/account_adapter.dart';
import 'package:PiliMax/utils/accounts/account_type_adapter.dart';
import 'package:PiliMax/utils/accounts/cookie_jar_adapter.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:PiliMax/utils/set_int_adapter.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_init_resource_tracker.dart';
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
  static Future<void>? _initFuture;
  static bool _initialized = false;
  static bool _hiveConfigured = false;

  static const _migrationStateBoxName = 'androidMmkvMigrationState';
  static const _androidMmkvBoxNames = {
    'userinfo',
    'localcache',
    'setting',
    'historyword',
    'video',
    'watchprogress',
    'reply',
  };

  static Future<void> init() {
    if (_initialized) return Future<void>.value();
    final pending = _initFuture;
    if (pending != null) return pending;
    final future = _initOnce();
    _initFuture = future;
    return future.whenComplete(() {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    });
  }

  static Future<void> _initOnce() async {
    _configureHive();
    final resources = StorageInitResourceTracker();
    try {
      resources.watchHiveBox<String>(_migrationStateBoxName);
      final migrationStateBox = resources.own(
        await Hive.openBox<String>(
          _migrationStateBoxName,
          compactionStrategy: (entries, deletedEntries) => deletedEntries > 4,
        ),
        (box) => box.close(),
      );
      final migrationState = HiveAndroidMmkvMigrationState(migrationStateBox);

      late Box<UserInfoData> nextUserInfo;
      late Box<dynamic> nextLocalCache;
      late Box<dynamic> nextSetting;
      late Box<dynamic> nextHistoryWord;
      late Box<dynamic> nextVideo;

      await Future.wait([
        openAndroidMmkvBackedBox<UserInfoData>(
          name: 'userInfo',
          valueEncoder: AndroidMmkvStorageCodec.encodeUserInfoData,
          valueDecoder: AndroidMmkvStorageCodec.decodeUserInfoData,
          migrationState: migrationState,
          openHive: () {
            resources.watchHiveBox<UserInfoData>('userInfo');
            return Hive.openBox<UserInfoData>(
              'userInfo',
              compactionStrategy: (int entries, int deletedEntries) {
                return deletedEntries > 2;
              },
            );
          },
        ).then((box) {
          nextUserInfo = resources.own(box, (box) => box.close());
        }),
        openAndroidMmkvBackedBox<dynamic>(
          name: 'localCache',
          valueEncoder: AndroidMmkvStorageCodec.encodeLocalCacheValue,
          valueDecoder: AndroidMmkvStorageCodec.decodeLocalCacheValue,
          migrationState: migrationState,
          openHive: () {
            resources.watchHiveBox('localCache');
            return Hive.openBox(
              'localCache',
              compactionStrategy: (int entries, int deletedEntries) {
                return deletedEntries > 4;
              },
            );
          },
        ).then((box) {
          nextLocalCache = resources.own(box, (box) => box.close());
        }),
        openAndroidMmkvBackedBox<dynamic>(
          name: 'setting',
          migrationState: migrationState,
          openHive: () {
            resources.watchHiveBox('setting');
            return Hive.openBox('setting');
          },
        ).then((box) {
          nextSetting = resources.own(box, (box) => box.close());
        }),
        openAndroidMmkvBackedBox<dynamic>(
          name: 'historyWord',
          migrationState: migrationState,
          openHive: () {
            resources.watchHiveBox('historyWord');
            return Hive.openBox(
              'historyWord',
              compactionStrategy: (int entries, int deletedEntries) {
                return deletedEntries > 10;
              },
            );
          },
        ).then((box) {
          nextHistoryWord = resources.own(box, (box) => box.close());
        }),
        openAndroidMmkvBackedBox<dynamic>(
          name: 'video',
          migrationState: migrationState,
          openHive: () {
            resources.watchHiveBox('video');
            return Hive.openBox('video');
          },
        ).then((box) {
          nextVideo = resources.own(box, (box) => box.close());
        }),
      ]);
      await _normalizeAutoClearCachePeriod(nextSetting);

      final nextWatchProgress = resources.own(
        await openAndroidMmkvBackedBox<int>(
          name: 'watchProgress',
          migrationState: migrationState,
          keyComparator: _intStrDescKeyComparator,
          loadMode: AndroidMmkvLoadMode.lazy,
          openHive: () {
            resources.watchHiveBox<int>('watchProgress');
            return Hive.openBox<int>(
              'watchProgress',
              keyComparator: _intStrDescKeyComparator,
              compactionStrategy: (entries, deletedEntries) {
                return deletedEntries > 4;
              },
            );
          },
        ),
        (box) => box.close(),
      );
      final nextWatchProgressStore = WatchProgressStore(
        nextWatchProgress,
        orderStore: nextLocalCache,
      );
      await nextWatchProgressStore.enforceLimit();

      final saveReply =
          nextSetting.get(
                SettingBoxKey.saveReply,
                defaultValue: true,
              )
              as bool;
      final Box<Uint8List>? nextReply;
      if (saveReply) {
        nextReply = resources.own<Box<Uint8List>>(
          await openAndroidMmkvBackedBox<Uint8List>(
            name: 'reply',
            migrationState: migrationState,
            keyComparator: _intStrDescKeyComparator,
            loadMode: AndroidMmkvLoadMode.lazy,
            openHive: () {
              resources.watchHiveBox<Uint8List>('reply');
              return Hive.openBox<Uint8List>(
                'reply',
                keyComparator: _intStrDescKeyComparator,
                compactionStrategy: (entries, deletedEntries) {
                  return deletedEntries > 10;
                },
              );
            },
          ),
          (box) => box.close(),
        );
      } else {
        nextReply = null;
      }
      final nextReplyCacheStore = ReplyCacheStore(
        nextReply,
        orderStore: nextLocalCache,
      );
      await nextReplyCacheStore.enforceLimit();

      resources
        ..watchHiveBox<LoginAccount>('account')
        ..watchHiveBox<LoginAccount>('accountQuarantine');
      await Accounts.init();

      userInfo = nextUserInfo;
      localCache = nextLocalCache;
      setting = nextSetting;
      historyWord = nextHistoryWord;
      video = nextVideo;
      _androidMmkvMigrationState = migrationStateBox;
      watchProgress = nextWatchProgress;
      watchProgressStore = nextWatchProgressStore;
      reply = nextReply;
      replyCacheStore = nextReplyCacheStore;
      _initialized = true;
      resources.commit();
    } catch (error, stackTrace) {
      await resources.rollback();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<AndroidMmkvRecoveryBackup> backupAndResetAndroidMmkvFailure(
    AndroidMmkvMigrationException failure,
  ) async {
    final boxName = failure.boxName.toLowerCase();
    if (!_androidMmkvBoxNames.contains(boxName)) {
      throw const AndroidMmkvRecoveryException('unknown_box');
    }
    _configureHive();
    final stateWasOpen = Hive.isBoxOpen(_migrationStateBoxName);
    final stateBox = stateWasOpen
        ? Hive.box<String>(_migrationStateBoxName)
        : await Hive.openBox<String>(
            _migrationStateBoxName,
            compactionStrategy: (entries, deletedEntries) => deletedEntries > 4,
          );
    try {
      return await AndroidMmkvRecoveryService(
        backupDirectory: Directory(
          path.join(appSupportDirPath, 'storage_recovery'),
        ),
        legacyHiveDirectory: Directory(path.join(appSupportDirPath, 'hive')),
        migrationState: HiveAndroidMmkvMigrationState(stateBox),
      ).backupAndReset(failure);
    } finally {
      if (!stateWasOpen) {
        await stateBox.close();
      }
    }
  }

  static void _configureHive() {
    if (_hiveConfigured) return;
    Hive.init(path.join(appSupportDirPath, 'hive'));
    regAdapter();
    _hiveConfigured = true;
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

  static Future<void> importAllJsonSettings(
    Map<String, dynamic> map,
  ) async {
    final importedSetting = map[setting.name];
    final importedVideo = map[video.name];
    if (importedSetting is! Map || importedVideo is! Map) {
      throw const FormatException('设置文件格式无效');
    }
    final settingValues = CacheAutoClearPeriod.normalizedSettingsCopy(
      importedSetting,
      periodKey: SettingBoxKey.autoClearCachePeriod,
    );
    final videoValues = Map<dynamic, dynamic>.from(importedVideo);

    final localCacheValues = <String, dynamic>{};

    // 导入 localCache 数据（如果存在）
    if (map.containsKey(localCache.name)) {
      final localCacheMap = map[localCache.name];
      if (localCacheMap is! Map) {
        throw const FormatException('设置文件格式无效');
      }
      for (final entry in localCacheMap.entries) {
        if (entry.key is! String) {
          throw const FormatException('设置文件格式无效');
        }
        final key = entry.key as String;
        if (!exportableLocalCacheKeys.contains(key)) {
          continue;
        }
        localCacheValues[key] = _decodeLocalCacheValue(key, entry.value);
      }
    }

    final settingSnapshot = setting.toMap();
    final videoSnapshot = video.toMap();
    final localCacheSnapshot = {
      for (final key in localCacheValues.keys)
        key: (
          exists: localCache.containsKey(key),
          value: localCache.get(key),
        ),
    };
    try {
      await _replaceBox(setting, settingValues);
      await _replaceBox(video, videoValues);
      await localCache.putAll(localCacheValues);
    } catch (error, stackTrace) {
      try {
        await _replaceBox(setting, settingSnapshot);
        await _replaceBox(video, videoSnapshot);
        for (final entry in localCacheSnapshot.entries) {
          if (entry.value.exists) {
            await localCache.put(entry.key, entry.value.value);
          } else {
            await localCache.delete(entry.key);
          }
        }
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _replaceBox(Box box, Map<dynamic, dynamic> values) async {
    await box.clear();
    await box.putAll(values);
  }

  static Future<void> _normalizeAutoClearCachePeriod(Box settingBox) async {
    final stored = settingBox.get(SettingBoxKey.autoClearCachePeriod);
    final normalized = CacheAutoClearPeriod.normalize(stored);
    if (stored != normalized) {
      await settingBox.put(SettingBoxKey.autoClearCachePeriod, normalized);
    }
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
      ?Accounts.accountQuarantine?.compact(),
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
      ?Accounts.accountQuarantine?.close(),
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
