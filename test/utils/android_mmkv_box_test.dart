import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/models/user/info.dart';
import 'package:PiliMax/utils/android/android_mmkv_box.dart';
import 'package:PiliMax/utils/android/android_mmkv_recovery.dart';
import 'package:PiliMax/utils/android/android_mmkv_storage_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;
  late List<String> hiveBoxNames;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pilimax_mmkv_test_');
    Hive.init(hiveDirectory.path);
  });

  setUp(() => hiveBoxNames = []);

  tearDown(() async {
    for (final name in hiveBoxNames) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box<dynamic>(name).close();
      }
      await Hive.deleteBoxFromDisk(name);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('first Android open migrates and records both markers', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'first_open');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.putAll(const {
      'theme': 'dark',
      'ids': <int>{1, 2, 3},
    });

    final box = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );

    expect(box.name, name.toLowerCase());
    expect(box.get('theme'), 'dark');
    expect(box.get('ids'), <int>{1, 2, 3});
    final marker = store.getRaw(
      AndroidMmkvStore.metaBox,
      AndroidMmkvStore.migrationKey(name),
    );
    expect(marker, '1');
    final consistencyToken = store.getRaw(
      AndroidMmkvStore.metaBox,
      AndroidMmkvStore.consistencyKey(name),
    );
    expect(consistencyToken, isNotNull);
    expect(
      store.getRaw(name, AndroidMmkvStore.consistencySentinelKey),
      consistencyToken,
    );
    expect(store.getState(name), AndroidMmkvMigrationState.complete);
    expect(hive.isOpen, isFalse);
    await box.close();
  });

  test('camel-case name survives two MMKV reopens', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'UserInfoCamelCase');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 42);

    final migrated = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );
    await migrated.close();

    for (var i = 0; i < 2; i++) {
      final reopened = await openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () => Future.error(StateError('Hive should not open')),
      );
      expect(reopened.name, name.toLowerCase());
      expect(reopened.get('value'), 42);
      await reopened.close();
    }
  });

  test(
    'completed migration never restores stale Hive after corruption',
    () async {
      final store = _MemoryAndroidMmkvStore();
      final name = _newHiveBoxName(hiveBoxNames, 'corrupt');
      final hive = await Hive.openBox<dynamic>(name);
      await hive.put('value', 'legacy');
      final migrated = await openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () => Future.value(hive),
      );
      await migrated.put('value', 'current');
      await migrated.close();
      store.putRaw(name, jsonEncode('broken'), 'not-json');

      var hiveOpenCount = 0;
      await expectLater(
        openAndroidMmkvBackedBox<dynamic>(
          name: name,
          isAndroid: true,
          store: store,
          migrationState: store,
          openHive: () {
            hiveOpenCount++;
            return Hive.openBox<dynamic>(name);
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(hiveOpenCount, 0);
      expect(store.getState(name), AndroidMmkvMigrationState.complete);
    },
  );

  test('completed migration rejects a missing MMKV integrity marker', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'missing_integrity');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 'legacy');
    final migrated = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );
    await migrated.close();
    store.clearBox(name);

    var hiveOpenCount = 0;
    await expectLater(
      openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () {
          hiveOpenCount++;
          return Hive.openBox<dynamic>(name);
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(hiveOpenCount, 0);
  });

  test(
    'legacy migration marker is not treated as a consistency token',
    () async {
      final store = _MemoryAndroidMmkvStore();
      final name = _newHiveBoxName(hiveBoxNames, 'legacy_marker');
      store.putRaw(
        AndroidMmkvStore.metaBox,
        AndroidMmkvStore.migrationKey(name),
        '1',
      );

      var hiveOpenCount = 0;
      await expectLater(
        openAndroidMmkvBackedBox<dynamic>(
          name: name,
          isAndroid: true,
          store: store,
          migrationState: store,
          openHive: () {
            hiveOpenCount++;
            return Hive.openBox<dynamic>(name);
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(hiveOpenCount, 0);
    },
  );

  test('migration rollback preserves MMKV when marker removal fails', () async {
    final store = _MemoryAndroidMmkvStore()..failCompleteState = true;
    final name = _newHiveBoxName(hiveBoxNames, 'rollback_marker_failure');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 'legacy');
    store.failMetaRemoval = true;

    await expectLater(
      openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () => Future.value(hive),
      ),
      throwsA(isA<StateError>()),
    );
    expect(hive.isOpen, isFalse);
    expect(store.getState(name), AndroidMmkvMigrationState.pending);
    final marker = store.getRaw(
      AndroidMmkvStore.metaBox,
      AndroidMmkvStore.migrationKey(name),
    );
    expect(marker, '1');
    final consistencyToken = store.getRaw(
      AndroidMmkvStore.metaBox,
      AndroidMmkvStore.consistencyKey(name),
    );
    expect(consistencyToken, isNotNull);
    expect(
      store.getRaw(name, AndroidMmkvStore.consistencySentinelKey),
      consistencyToken,
    );
    expect(
      store.getRaw(
        AndroidMmkvStore.metaBox,
        AndroidMmkvStore.consistencyKey(name),
      ),
      isNotNull,
    );
    expect(store.exportBox(name), isNot('{}'));
  });

  test(
    'migration rollback stays fail-closed when MMKV cleanup fails',
    () async {
      final store = _MemoryAndroidMmkvStore()
        ..failCompleteState = true
        ..failClearBox = true;
      final name = _newHiveBoxName(hiveBoxNames, 'rollback_clear_failure');
      final hive = await Hive.openBox<dynamic>(name);
      await hive.put('value', 'legacy');

      await expectLater(
        openAndroidMmkvBackedBox<dynamic>(
          name: name,
          isAndroid: true,
          store: store,
          migrationState: store,
          openHive: () => Future.value(hive),
        ),
        throwsA(isA<StateError>()),
      );
      expect(store.getState(name), AndroidMmkvMigrationState.pending);
      expect(
        store.getRaw(
          AndroidMmkvStore.metaBox,
          AndroidMmkvStore.migrationKey(name),
        ),
        isNull,
      );
      expect(store.exportBox(name), isNot('{}'));

      await expectLater(
        openAndroidMmkvBackedBox<dynamic>(
          name: name,
          isAndroid: true,
          store: store,
          migrationState: store,
          openHive: () => Future.error(StateError('must fail closed')),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('first migration failure returns Hive and clears state', () async {
    final store = _MemoryAndroidMmkvStore()..failNextSync = true;
    final name = _newHiveBoxName(hiveBoxNames, 'marker_failure');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 'legacy');

    final box = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );

    expect(identical(box, hive), isTrue);
    expect(box.get('value'), 'legacy');
    expect(box.isOpen, isTrue);
    expect(store.getState(name), isNull);
    expect(
      store.getRaw(
        AndroidMmkvStore.metaBox,
        AndroidMmkvStore.migrationKey(name),
      ),
      isNull,
    );
    expect(
      store.getRaw(
        AndroidMmkvStore.metaBox,
        AndroidMmkvStore.consistencyKey(name),
      ),
      isNull,
    );
    await box.close();
  });

  test('migration rejects a decodable value mismatch', () async {
    final store = _MemoryAndroidMmkvStore()..corruptNextReplace = true;
    final name = _newHiveBoxName(hiveBoxNames, 'value_mismatch');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 'legacy');

    final box = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );

    expect(identical(box, hive), isTrue);
    expect(box.get('value'), 'legacy');
    expect(store.getState(name), isNull);
    expect(store.exportBox(name), '{}');
    await box.close();
  });

  test('unsupported migration keeps Hive as rollback source', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'unsupported');
    final hive = await Hive.openBox<dynamic>(name);
    final unsupported = DateTime.utc(2026, 7, 10);
    await hive.put('date', unsupported);

    final box = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );

    expect(identical(box, hive), isTrue);
    expect(box.get('date'), unsupported);
    expect(store.getState(name), isNull);
    await box.close();
  });

  test('complete state refuses stale Hive when MMKV is unavailable', () async {
    final store = _MemoryAndroidMmkvStore(available: false);
    final name = _newHiveBoxName(hiveBoxNames, 'unavailable');
    await store.setState(name, AndroidMmkvMigrationState.complete);
    var hiveOpenCount = 0;

    await expectLater(
      openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () {
          hiveOpenCount++;
          return Hive.openBox<dynamic>(name);
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(hiveOpenCount, 0);
  });

  test('absent state uses Hive while MMKV is unavailable', () async {
    final store = _MemoryAndroidMmkvStore(available: false);
    final name = _newHiveBoxName(hiveBoxNames, 'fresh_unavailable');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 'legacy');

    final box = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );

    expect(identical(box, hive), isTrue);
    expect(box.get('value'), 'legacy');
    expect(store.getState(name), isNull);
    await box.close();
  });

  test('pending state refuses Hive while MMKV is unavailable', () async {
    final store = _MemoryAndroidMmkvStore(available: false);
    final name = _newHiveBoxName(hiveBoxNames, 'pending_unavailable');
    await store.setState(name, AndroidMmkvMigrationState.pending);
    var hiveOpenCount = 0;

    await expectLater(
      openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () {
          hiveOpenCount++;
          return Hive.openBox<dynamic>(name);
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(hiveOpenCount, 0);
  });

  test('internal marker restores a missing external complete state', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'marker_recovery');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.put('value', 'migrated');
    final migrated = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );
    await migrated.close();
    await store.clearState(name);

    final reopened = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.error(StateError('Hive should not open')),
    );

    expect(reopened.get('value'), 'migrated');
    expect(store.getState(name), AndroidMmkvMigrationState.complete);
    await reopened.close();
  });

  test(
    'lazy valuesBetween materializes and add uses the highest key',
    () async {
      final store = _MemoryAndroidMmkvStore();
      final name = _newHiveBoxName(hiveBoxNames, 'lazy');
      final hive = await Hive.openBox<dynamic>(name);
      await hive.putAll({2: 'two', 7: 'seven'});
      final migrated = await openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () => Future.value(hive),
      );
      await migrated.close();

      final lazy = await openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        loadMode: AndroidMmkvLoadMode.lazy,
        openHive: () => Future.error(StateError('Hive should not open')),
      );
      expect(lazy.lazy, isFalse);
      expect(lazy.valuesBetween(startKey: 2, endKey: 7), ['two', 'seven']);
      expect(await lazy.add('eight'), 8);
      expect(lazy.get(8), 'eight');
      await lazy.close();
    },
  );

  test('lazy bulk materialization reports a corrupt value', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'lazy_corrupt');
    final hive = await Hive.openBox<dynamic>(name);
    await hive.putAll({for (var i = 0; i < 9; i++) 'key$i': i});
    final migrated = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () => Future.value(hive),
    );
    await migrated.close();
    store.putRaw(name, jsonEncode('key4'), 'not-json');

    final lazy = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      loadMode: AndroidMmkvLoadMode.lazy,
      openHive: () => Future.error(StateError('Hive should not open')),
    );

    expect(() => lazy.values.toList(), throwsA(isA<StateError>()));
    await lazy.close();
  });

  test(
    'lazy open rejects a malformed key list instead of dropping entries',
    () async {
      final store = _MemoryAndroidMmkvStore()..malformedKeys = true;
      final name = _newHiveBoxName(hiveBoxNames, 'lazy_bad_keys');
      final box = AndroidMmkvBackedBox<dynamic>(
        name,
        store: store,
        loadMode: AndroidMmkvLoadMode.lazy,
      );

      expect(box.tryLoadFromMmkv(), isFalse);
      await box.close();
    },
  );

  test('logical key equal to the raw sentinel remains usable', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'sentinel_named_key');
    final box = AndroidMmkvBackedBox<dynamic>(name, store: store);

    await box.put(AndroidMmkvStore.consistencySentinelKey, 'user-value');
    expect(box.containsKey(AndroidMmkvStore.consistencySentinelKey), isTrue);
    expect(box.get(AndroidMmkvStore.consistencySentinelKey), 'user-value');
    expect(box.keys, contains(AndroidMmkvStore.consistencySentinelKey));

    final reopened = AndroidMmkvBackedBox<dynamic>(name, store: store);
    expect(reopened.tryLoadFromMmkv(), isTrue);
    expect(reopened.get(AndroidMmkvStore.consistencySentinelKey), 'user-value');
    await box.close();
    await reopened.close();
  });

  test('clear resets the auto-increment key', () async {
    final store = _MemoryAndroidMmkvStore();
    final box = AndroidMmkvBackedBox<dynamic>('clear_add', store: store);

    expect(await box.add('first'), 0);
    await box.clear();
    expect(await box.add('second'), 0);

    await box.close();
  });

  test('clear preserves only the raw consistency sentinel', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'clear_sentinel');
    const token = 'token';
    final box = AndroidMmkvBackedBox<dynamic>(
      name,
      store: store,
      consistencyToken: token,
    );
    await box.put('value', 'before');

    expect(await box.clear(), 1);
    expect(box.length, 0);
    expect(store.getRaw(name, AndroidMmkvStore.consistencySentinelKey), token);
    expect(
      store.exportKeys(name),
      jsonEncode([AndroidMmkvStore.consistencySentinelKey]),
    );
    expect(box.tryLoadFromMmkv(), isTrue);
    await box.close();
  });

  test('deleteFromDisk leaves a reopenable empty migrated box', () async {
    final store = _MemoryAndroidMmkvStore();
    final name = _newHiveBoxName(hiveBoxNames, 'delete_disk');
    final box = AndroidMmkvBackedBox<dynamic>(
      name,
      store: store,
      consistencyToken: 'token',
    );
    await box.put('value', 'before');

    await box.deleteFromDisk();
    expect(box.isOpen, isFalse);
    expect(
      store.getRaw(name, AndroidMmkvStore.consistencySentinelKey),
      'token',
    );
    final reopened = AndroidMmkvBackedBox<dynamic>(
      name,
      store: store,
      consistencyToken: 'token',
    );
    expect(reopened.tryLoadFromMmkv(), isTrue);
    expect(reopened.isEmpty, isTrue);
    await reopened.close();
  });

  test('add starts at zero when existing integer keys are negative', () async {
    final store = _MemoryAndroidMmkvStore();
    final box = AndroidMmkvBackedBox<dynamic>('negative_add', store: store);

    await box.put(-5, 'negative');
    expect(await box.add('zero'), 0);

    await box.close();
  });

  test(
    'default key ordering matches Hive for integer and string keys',
    () async {
      final store = _MemoryAndroidMmkvStore();
      final box = AndroidMmkvBackedBox<dynamic>('mixed_keys', store: store);

      await box.put('2', 'string-two');
      await box.put(2, 'integer-two');
      await box.put('10', 'string-ten');
      await box.put(-1, 'negative');

      expect(box.keys, [-1, 2, '10', '2']);
      await box.close();
    },
  );

  test('typed values survive codec round trips', () async {
    final store = _MemoryAndroidMmkvStore();
    final user = UserInfoData(
      isLogin: true,
      mid: 123,
      uname: 'Pili',
      levelInfo: LevelInfo(currentLevel: 6, currentExp: 10, nextExp: 10),
    );
    final box = AndroidMmkvBackedBox<UserInfoData>(
      'UserInfo',
      store: store,
      valueEncoder: AndroidMmkvStorageCodec.encodeUserInfoData,
      valueDecoder: AndroidMmkvStorageCodec.decodeUserInfoData,
    );
    await box.put('user', user);
    final reopened = AndroidMmkvBackedBox<UserInfoData>(
      'userinfo',
      store: store,
      valueEncoder: AndroidMmkvStorageCodec.encodeUserInfoData,
      valueDecoder: AndroidMmkvStorageCodec.decodeUserInfoData,
    );
    expect(reopened.tryLoadFromMmkv(), isTrue);
    expect(reopened.get('user'), user);
    await box.close();
    await reopened.close();
  });

  test('verified recovery backup resets only the failed box', () async {
    final store = _MemoryAndroidMmkvStore();
    const name = 'setting';
    const otherName = 'video';
    final migrationKey = AndroidMmkvStore.migrationKey(name);
    final consistencyKey = AndroidMmkvStore.consistencyKey(name);
    final otherMigrationKey = AndroidMmkvStore.migrationKey(otherName);
    store
      ..putRaw(name, 'sensitive-key', 'corrupt-value')
      ..putRaw(otherName, 'other-key', 'other-value')
      ..putRaw(AndroidMmkvStore.metaBox, migrationKey, 'broken')
      ..putRaw(AndroidMmkvStore.metaBox, consistencyKey, 'old-token')
      ..putRaw(AndroidMmkvStore.metaBox, otherMigrationKey, '1');
    await store.setState(name, AndroidMmkvMigrationState.complete);
    await store.setState(otherName, AndroidMmkvMigrationState.complete);
    final backupDirectory = Directory(
      '${hiveDirectory.path}${Platform.pathSeparator}recovery',
    );
    File(
      '${hiveDirectory.path}${Platform.pathSeparator}$name.hive',
    ).writeAsBytesSync(const [1, 2, 3, 4]);
    final service = AndroidMmkvRecoveryService(
      backupDirectory: backupDirectory,
      legacyHiveDirectory: hiveDirectory,
      migrationState: store,
      store: store,
      now: () => DateTime.utc(2026, 7, 25, 12),
    );
    final failure = AndroidMmkvMigrationException(
      boxName: name,
      phase: AndroidMmkvMigrationPhase.metadata,
      code: 'invalid_migration_marker',
      recoveryAction: AndroidMmkvRecoveryAction.resetBox,
    );

    final backup = await service.backupAndReset(failure);

    expect(backup.file.existsSync(), isTrue);
    final backupJson =
        jsonDecode(backup.file.readAsStringSync()) as Map<String, dynamic>;
    expect(backupJson['boxName'], name);
    expect(backupJson['boxSnapshot'], contains('corrupt-value'));
    expect(backupJson['sha256'], backup.sha256);
    final legacyHive = backupJson['legacyHive'] as Map<String, dynamic>;
    expect(legacyHive['present'], isTrue);
    expect(
      File(
        '${backup.file.parent.path}${Platform.pathSeparator}legacy.hive',
      ).readAsBytesSync(),
      const [1, 2, 3, 4],
    );
    expect(store.getState(name), AndroidMmkvMigrationState.complete);
    expect(
      store.getRaw(AndroidMmkvStore.metaBox, migrationKey),
      '1',
    );
    final token = store.getRaw(AndroidMmkvStore.metaBox, consistencyKey);
    expect(token, isNotNull);
    expect(
      store.getRaw(name, AndroidMmkvStore.consistencySentinelKey),
      token,
    );
    expect(
      store.exportKeys(name),
      jsonEncode([AndroidMmkvStore.consistencySentinelKey]),
    );

    expect(store.getRaw(otherName, 'other-key'), 'other-value');
    expect(
      store.getRaw(AndroidMmkvStore.metaBox, otherMigrationKey),
      '1',
    );
    expect(store.getState(otherName), AndroidMmkvMigrationState.complete);

    var hiveOpened = false;
    final reopened = await openAndroidMmkvBackedBox<dynamic>(
      name: name,
      isAndroid: true,
      store: store,
      migrationState: store,
      openHive: () {
        hiveOpened = true;
        return Future.error(StateError('stale Hive must stay closed'));
      },
    );
    expect(hiveOpened, isFalse);
    expect(reopened.isEmpty, isTrue);
    await reopened.close();
  });

  test('recovery backup preserves a lone Hive compaction candidate', () async {
    final store = _MemoryAndroidMmkvStore();
    const name = 'historyword';
    final migrationKey = AndroidMmkvStore.migrationKey(name);
    store
      ..putRaw(name, 'key', 'partial-mmkv')
      ..putRaw(AndroidMmkvStore.metaBox, migrationKey, 'broken');
    await store.setState(name, AndroidMmkvMigrationState.pending);
    final legacyDirectory = Directory(
      '${hiveDirectory.path}${Platform.pathSeparator}legacy-hivec',
    )..createSync();
    File(
      '${legacyDirectory.path}${Platform.pathSeparator}$name.hivec',
    ).writeAsBytesSync(const [9, 8, 7, 6]);
    final service = AndroidMmkvRecoveryService(
      backupDirectory: Directory(
        '${hiveDirectory.path}${Platform.pathSeparator}recovery-hivec',
      ),
      legacyHiveDirectory: legacyDirectory,
      migrationState: store,
      store: store,
    );
    final failure = AndroidMmkvMigrationException(
      boxName: name,
      phase: AndroidMmkvMigrationPhase.metadata,
      code: 'invalid_migration_marker',
      recoveryAction: AndroidMmkvRecoveryAction.resetBox,
    );

    final backup = await service.backupAndReset(failure);
    final backupJson =
        jsonDecode(backup.file.readAsStringSync()) as Map<String, dynamic>;
    final legacyHive = backupJson['legacyHive'] as Map<String, dynamic>;
    expect(legacyHive['present'], isTrue);
    expect((legacyHive['files'] as List), hasLength(1));
    expect(
      File(
        '${backup.file.parent.path}${Platform.pathSeparator}legacy.hivec',
      ).readAsBytesSync(),
      const [9, 8, 7, 6],
    );
  });

  test('backup failure leaves the failed box and metadata untouched', () async {
    final store = _MemoryAndroidMmkvStore();
    const name = 'setting';
    final migrationKey = AndroidMmkvStore.migrationKey(name);
    store
      ..putRaw(name, 'key', 'value')
      ..putRaw(AndroidMmkvStore.metaBox, migrationKey, 'broken');
    await store.setState(name, AndroidMmkvMigrationState.complete);
    final notDirectory = File(
      '${hiveDirectory.path}${Platform.pathSeparator}not-a-directory',
    );
    await notDirectory.writeAsString('occupied');
    final service = AndroidMmkvRecoveryService(
      backupDirectory: Directory(notDirectory.path),
      migrationState: store,
      store: store,
    );
    final failure = AndroidMmkvMigrationException(
      boxName: name,
      phase: AndroidMmkvMigrationPhase.metadata,
      code: 'invalid_migration_marker',
      recoveryAction: AndroidMmkvRecoveryAction.resetBox,
    );

    await expectLater(
      service.backupAndReset(failure),
      throwsA(isA<AndroidMmkvRecoveryException>()),
    );
    expect(store.getRaw(name, 'key'), 'value');
    expect(store.getRaw(AndroidMmkvStore.metaBox, migrationKey), 'broken');
    expect(store.getState(name), AndroidMmkvMigrationState.complete);
  });

  for (final testCase
      in <
        ({
          String name,
          String code,
          bool enteringStateFails,
          void Function(_MemoryAndroidMmkvStore store) inject,
        })
      >[
        (
          name: 'enter recovering state',
          code: 'recovery_state_write_failed',
          enteringStateFails: true,
          inject: (store) => store.failRecoveringState = true,
        ),
        (
          name: 'box clear',
          code: 'box_reset_failed',
          enteringStateFails: false,
          inject: (store) => store.failClearBox = true,
        ),
        (
          name: 'recovery guard write',
          code: 'recovery_guard_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failRecoveryGuardWrite = true,
        ),
        (
          name: 'recovery guard sync',
          code: 'recovery_guard_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failSyncOnCall[AndroidMmkvStore.metaBox] = 1,
        ),
        (
          name: 'box clear sync',
          code: 'box_reset_failed',
          enteringStateFails: false,
          inject: (store) => store.failSyncOnCall['setting'] = 1,
        ),
        (
          name: 'metadata remove',
          code: 'metadata_reset_failed',
          enteringStateFails: false,
          inject: (store) => store.failMetaRemoval = true,
        ),
        (
          name: 'sentinel write',
          code: 'sentinel_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failSentinelWrite = true,
        ),
        (
          name: 'sentinel sync',
          code: 'sentinel_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failSyncOnCall['setting'] = 2,
        ),
        (
          name: 'metadata write',
          code: 'metadata_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failMetadataWrite = true,
        ),
        (
          name: 'metadata sync',
          code: 'metadata_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failSyncOnCall[AndroidMmkvStore.metaBox] = 3,
        ),
        (
          name: 'complete state write',
          code: 'state_write_failed',
          enteringStateFails: false,
          inject: (store) => store.failCompleteState = true,
        ),
        (
          name: 'recovery guard clear',
          code: 'recovery_guard_clear_failed',
          enteringStateFails: false,
          inject: (store) => store.failRecoveryGuardRemoval = true,
        ),
      ]) {
    test(
      '${testCase.name} failure keeps backup and remains fail-closed',
      () async {
        final store = _MemoryAndroidMmkvStore();
        const name = 'setting';
        const otherName = 'video';
        final migrationKey = AndroidMmkvStore.migrationKey(name);
        store
          ..putRaw(name, 'key', 'faulty-value')
          ..putRaw(otherName, 'key', 'other-value')
          ..putRaw(AndroidMmkvStore.metaBox, migrationKey, 'broken');
        await store.setState(name, AndroidMmkvMigrationState.complete);
        testCase.inject(store);
        final safeName = testCase.name.replaceAll(' ', '-');
        final backupDirectory = Directory(
          '${hiveDirectory.path}${Platform.pathSeparator}'
          'recovery-$safeName',
        );
        final service = AndroidMmkvRecoveryService(
          backupDirectory: backupDirectory,
          migrationState: store,
          store: store,
        );
        final failure = AndroidMmkvMigrationException(
          boxName: name,
          phase: AndroidMmkvMigrationPhase.metadata,
          code: 'invalid_migration_marker',
          recoveryAction: AndroidMmkvRecoveryAction.resetBox,
        );

        await expectLater(
          service.backupAndReset(failure),
          throwsA(
            isA<AndroidMmkvRecoveryException>().having(
              (error) => error.code,
              'code',
              testCase.code,
            ),
          ),
        );

        final manifests = backupDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('manifest.json'))
            .toList();
        expect(manifests, hasLength(1));
        expect(jsonDecode(manifests.single.readAsStringSync()), isA<Map>());
        expect(store.getRaw(otherName, 'key'), 'other-value');
        expect(
          store.getState(name),
          testCase.enteringStateFails
              ? AndroidMmkvMigrationState.complete
              : AndroidMmkvMigrationState.recovering,
        );
        if (testCase.enteringStateFails) {
          expect(store.getRaw(name, 'key'), 'faulty-value');
          expect(
            store.getRaw(AndroidMmkvStore.metaBox, migrationKey),
            'broken',
          );
        }

        var hiveOpened = false;
        await expectLater(
          openAndroidMmkvBackedBox<dynamic>(
            name: name,
            isAndroid: true,
            store: store,
            migrationState: store,
            openHive: () {
              hiveOpened = true;
              return Future.error(StateError('stale Hive must stay closed'));
            },
          ),
          throwsA(
            isA<AndroidMmkvMigrationException>()
                .having(
                  (error) => error.code,
                  'code',
                  testCase.enteringStateFails
                      ? 'invalid_migration_marker'
                      : 'recovery_in_progress',
                )
                .having(
                  (error) => error.recoveryAction,
                  'recoveryAction',
                  AndroidMmkvRecoveryAction.resetBox,
                ),
          ),
        );
        expect(hiveOpened, isFalse);
      },
    );
  }

  test(
    'unknown complete write is accepted only after full validation',
    () async {
      final store = _MemoryAndroidMmkvStore()
        ..completeStateWritesThenThrows = true;
      const name = 'setting';
      store
        ..putRaw(name, 'key', 'faulty-value')
        ..putRaw(
          AndroidMmkvStore.metaBox,
          AndroidMmkvStore.migrationKey(name),
          'broken',
        );
      await store.setState(name, AndroidMmkvMigrationState.pending);
      final service = AndroidMmkvRecoveryService(
        backupDirectory: Directory(
          '${hiveDirectory.path}${Platform.pathSeparator}'
          'recovery-unknown-complete-valid',
        ),
        migrationState: store,
        store: store,
      );
      final failure = AndroidMmkvMigrationException(
        boxName: name,
        phase: AndroidMmkvMigrationPhase.metadata,
        code: 'invalid_migration_marker',
        recoveryAction: AndroidMmkvRecoveryAction.resetBox,
      );

      final backup = await service.backupAndReset(failure);

      expect(backup.file.existsSync(), isTrue);
      expect(store.getState(name), AndroidMmkvMigrationState.complete);
      expect(
        store.getRaw(
          AndroidMmkvStore.metaBox,
          AndroidMmkvStore.recoveryKey(name),
        ),
        isNull,
      );
      var hiveOpened = false;
      final reopened = await openAndroidMmkvBackedBox<dynamic>(
        name: name,
        isAndroid: true,
        store: store,
        migrationState: store,
        openHive: () {
          hiveOpened = true;
          return Future.error(StateError('stale Hive must stay closed'));
        },
      );
      expect(hiveOpened, isFalse);
      expect(reopened.isEmpty, isTrue);
      await reopened.close();
    },
  );

  test(
    'unknown incomplete commit stays guarded when recovering restore fails',
    () async {
      final store = _MemoryAndroidMmkvStore()
        ..completeStateWritesThenThrows = true
        ..corruptBoxOnUnknownComplete = true
        ..failRecoveringStateAfterFirst = true;
      const name = 'setting';
      const otherName = 'video';
      store
        ..putRaw(name, 'key', 'faulty-value')
        ..putRaw(otherName, 'key', 'other-value')
        ..putRaw(
          AndroidMmkvStore.metaBox,
          AndroidMmkvStore.migrationKey(name),
          'broken',
        );
      await store.setState(name, AndroidMmkvMigrationState.pending);
      final backupDirectory = Directory(
        '${hiveDirectory.path}${Platform.pathSeparator}'
        'recovery-unknown-complete-invalid',
      );
      final service = AndroidMmkvRecoveryService(
        backupDirectory: backupDirectory,
        migrationState: store,
        store: store,
      );
      final failure = AndroidMmkvMigrationException(
        boxName: name,
        phase: AndroidMmkvMigrationPhase.metadata,
        code: 'invalid_migration_marker',
        recoveryAction: AndroidMmkvRecoveryAction.resetBox,
      );

      await expectLater(
        service.backupAndReset(failure),
        throwsA(
          isA<AndroidMmkvRecoveryException>().having(
            (error) => error.code,
            'code',
            'state_write_failed',
          ),
        ),
      );

      expect(
        backupDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('manifest.json')),
        hasLength(1),
      );
      expect(store.getRaw(otherName, 'key'), 'other-value');
      expect(store.getState(name), AndroidMmkvMigrationState.complete);
      expect(
        store.getRaw(
          AndroidMmkvStore.metaBox,
          AndroidMmkvStore.recoveryKey(name),
        ),
        '1',
      );
      var hiveOpened = false;
      await expectLater(
        openAndroidMmkvBackedBox<dynamic>(
          name: name,
          isAndroid: true,
          store: store,
          migrationState: store,
          openHive: () {
            hiveOpened = true;
            return Future.error(StateError('stale Hive must stay closed'));
          },
        ),
        throwsA(
          isA<AndroidMmkvMigrationException>().having(
            (error) => error.code,
            'code',
            'recovery_in_progress',
          ),
        ),
      );
      expect(hiveOpened, isFalse);
    },
  );

  test('retry-only migration failures cannot reset data', () async {
    final store = _MemoryAndroidMmkvStore();
    const name = 'setting';
    store.putRaw(name, 'key', 'value');
    final service = AndroidMmkvRecoveryService(
      backupDirectory: hiveDirectory,
      migrationState: store,
      store: store,
    );
    final failure = AndroidMmkvMigrationException(
      boxName: name,
      phase: AndroidMmkvMigrationPhase.availability,
      code: 'store_unavailable_with_state',
      recoveryAction: AndroidMmkvRecoveryAction.retry,
    );

    await expectLater(
      service.backupAndReset(failure),
      throwsA(
        isA<AndroidMmkvRecoveryException>().having(
          (error) => error.code,
          'code',
          'reset_not_allowed',
        ),
      ),
    );
    expect(store.getRaw(name, 'key'), 'value');
  });
}

String _newHiveBoxName(List<String> names, String suffix) {
  final name = 'mmkv_${suffix}_${DateTime.now().microsecondsSinceEpoch}';
  names.add(name);
  return name;
}

final class _MemoryAndroidMmkvStore
    implements AndroidMmkvStoreBackend, AndroidMmkvMigrationStateBackend {
  _MemoryAndroidMmkvStore({
    this.available = true,
  });

  final bool available;
  bool failNextSync = false;
  bool corruptNextReplace = false;
  bool failMetaRemoval = false;
  bool failRecoveringState = false;
  bool failRecoveringStateAfterFirst = false;
  bool failCompleteState = false;
  bool completeStateWritesThenThrows = false;
  bool corruptBoxOnUnknownComplete = false;
  bool failClearBox = false;
  bool failSentinelWrite = false;
  bool failMetadataWrite = false;
  bool failRecoveryGuardWrite = false;
  bool failRecoveryGuardRemoval = false;
  bool malformedKeys = false;
  final Map<String, int> failSyncOnCall = {};
  final Map<String, int> _syncCallCount = {};
  int _recoveringStateWriteCount = 0;
  final Map<String, Map<String, String>> _boxes = {};
  final Map<String, String> _states = {};

  @override
  bool get isAvailable => available;

  @override
  String? getState(String name) => _states[name.toLowerCase()];

  @override
  Future<void> setState(String name, String state) async {
    if (state == AndroidMmkvMigrationState.recovering) {
      _recoveringStateWriteCount++;
      if (failRecoveringState ||
          (failRecoveringStateAfterFirst && _recoveringStateWriteCount > 1)) {
        throw StateError('recovery state write failed');
      }
    }
    if (completeStateWritesThenThrows &&
        state == AndroidMmkvMigrationState.complete) {
      _states[name.toLowerCase()] = state;
      if (corruptBoxOnUnknownComplete) {
        (_boxes[name.toLowerCase()] ??= {})['"unexpected"'] = '{"value":true}';
      }
      throw StateError('state write result unknown');
    }
    if (failCompleteState && state == AndroidMmkvMigrationState.complete) {
      throw StateError('state write failed');
    }
    _states[name.toLowerCase()] = state;
  }

  @override
  Future<void> clearState(String name) async {
    _states.remove(name.toLowerCase());
  }

  @override
  bool clearBox(String name) {
    if (failClearBox) return false;
    _boxes[name] = {};
    return true;
  }

  @override
  String? exportBox(String name) => jsonEncode(_boxes[name] ?? const {});

  @override
  String? exportKeys(String name) => malformedKeys
      ? jsonEncode([123])
      : jsonEncode((_boxes[name] ?? const {}).keys.toList());

  @override
  String? getRaw(String name, String key) => _boxes[name]?[key];

  @override
  bool containsKey(String name, String key) =>
      _boxes[name]?.containsKey(key) ?? false;

  @override
  bool putRaw(String name, String key, String value) {
    if (failRecoveryGuardWrite && key.startsWith('recovering:')) {
      return false;
    }
    if (failSentinelWrite && key == AndroidMmkvStore.consistencySentinelKey) {
      return false;
    }
    if (failMetadataWrite &&
        name == AndroidMmkvStore.metaBox &&
        (key.startsWith('migrated:') || key.startsWith('consistency:'))) {
      return false;
    }
    (_boxes[name] ??= {})[key] = value;
    return true;
  }

  @override
  bool putAllRaw(String name, Map<String, String> entries) {
    (_boxes[name] ??= {}).addAll(entries);
    return true;
  }

  @override
  bool removeRaw(String name, String key) {
    if (failRecoveryGuardRemoval && key.startsWith('recovering:')) {
      return false;
    }
    if (failMetaRemoval && name == AndroidMmkvStore.metaBox) return false;
    _boxes[name]?.remove(key);
    return true;
  }

  @override
  bool removeAllRaw(String name, Iterable<String> keys) {
    for (final key in keys) {
      _boxes[name]?.remove(key);
    }
    return true;
  }

  @override
  bool replaceBox(String name, String json) {
    _boxes[name] = (jsonDecode(json) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
    if (corruptNextReplace && _boxes[name]!.isNotEmpty) {
      corruptNextReplace = false;
      _boxes[name]![_boxes[name]!.keys.first] = jsonEncode({
        'value': 'changed',
      });
    }
    return true;
  }

  @override
  bool sync(String name) {
    final call = (_syncCallCount[name] ?? 0) + 1;
    _syncCallCount[name] = call;
    if (failSyncOnCall[name] == call) return false;
    if (failNextSync) {
      failNextSync = false;
      return false;
    }
    return true;
  }
}
