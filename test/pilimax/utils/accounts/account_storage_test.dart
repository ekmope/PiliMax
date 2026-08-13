import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/account_adapter.dart';
import 'package:PiliMax/pilimax/utils/accounts/account_storage.dart';
import 'package:PiliMax/utils/accounts/account_type_adapter.dart';
import 'package:PiliMax/utils/accounts/cookie_jar_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;
  late _MemoryAccountSecretStore secretStore;

  setUpAll(() {
    Hive
      ..registerAdapter(BiliCookieJarAdapter())
      ..registerAdapter(LoginAccountAdapter())
      ..registerAdapter(AccountTypeAdapter());
  });

  setUp(() async {
    await Hive.close();
    hiveDirectory = await Directory.systemTemp.createTemp(
      'pilimax_secure_account_test_',
    );
    Hive.init(hiveDirectory.path);
    secretStore = _MemoryAccountSecretStore();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('migrates legacy accounts and removes plaintext storage', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put(
      '24680',
      _account(
        mid: '24680',
        session: 'legacy-session-secret',
        accessKey: 'legacy-access-secret',
      ),
    );
    await legacy.close();

    final storage = AccountStorage(secretStore: secretStore);
    final result = await storage.open();

    expect(result.requiresReauthentication, isFalse);
    expect(result.account.get('24680')?.mid, 24680);
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isFalse,
    );

    await result.quarantine.close();
    await result.account.close();
    final encryptedBytes = await _boxBytes(
      hiveDirectory,
      AccountStorage.accountBoxName,
    );
    final encodedBytes = latin1.decode(encryptedBytes, allowInvalid: true);
    expect(encodedBytes, isNot(contains('legacy-session-secret')));
    expect(encodedBytes, isNot(contains('legacy-access-secret')));

    final reopened = await storage.open();
    expect(reopened.account.get('24680')?.csrf, 'csrf-24680');
  });

  test('retries safely when verification state write is interrupted', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put('13579', _account(mid: '13579'));
    await legacy.close();
    secretStore.failOnceForValue = 'verified';

    await expectLater(
      AccountStorage(secretStore: secretStore).open(),
      throwsA(
        isA<AccountStorageException>().having(
          (error) => error.code,
          'code',
          'secure_storage_write_failed',
        ),
      ),
    );
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isTrue,
    );

    final result = await AccountStorage(secretStore: secretStore).open();
    expect(result.account.get('13579')?.mid, 13579);
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isFalse,
    );
  });

  test('resumes verified migration after legacy deletion', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put('97531', _account(mid: '97531'));
    await legacy.close();
    secretStore.failOnceForValue = 'complete';

    await expectLater(
      AccountStorage(secretStore: secretStore).open(),
      throwsA(isA<AccountStorageException>()),
    );
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isFalse,
    );

    final result = await AccountStorage(secretStore: secretStore).open();
    expect(result.account.get('97531')?.mid, 97531);
    expect(result.requiresReauthentication, isFalse);
  });

  test('missing secure key discards sessions and requires login', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put('86420', _account(mid: '86420'));
    await legacy.close();
    final storage = AccountStorage(secretStore: secretStore);
    final migrated = await storage.open();
    await migrated.quarantine.close();
    await migrated.account.close();

    secretStore.clear();
    final recovered = await storage.open();
    expect(recovered.requiresReauthentication, isTrue);
    expect(recovered.account, isEmpty);
    expect(recovered.quarantine, isEmpty);

    await storage.markReauthenticated();
    await recovered.quarantine.close();
    await recovered.account.close();
    final reopened = await storage.open();
    expect(reopened.requiresReauthentication, isFalse);
  });

  test('missing secure key preserves recoverable legacy sessions', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put('75319', _account(mid: '75319'));
    await legacy.close();
    secretStore.failOnceForValue = 'verified';

    await expectLater(
      AccountStorage(secretStore: secretStore).open(),
      throwsA(isA<AccountStorageException>()),
    );
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isTrue,
    );

    secretStore.clear();
    final recovered = await AccountStorage(secretStore: secretStore).open();

    expect(recovered.requiresReauthentication, isFalse);
    expect(recovered.account.get('75319')?.mid, 75319);
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isFalse,
    );
  });

  test(
    'missing verified secure box resets safely when legacy is gone',
    () async {
      final legacy = await Hive.openBox<LoginAccount>(
        AccountStorage.legacyAccountBoxName,
      );
      await legacy.put('64280', _account(mid: '64280'));
      await legacy.close();
      secretStore.failOnceForValue = 'complete';

      await expectLater(
        AccountStorage(secretStore: secretStore).open(),
        throwsA(isA<AccountStorageException>()),
      );
      await Hive.deleteBoxFromDisk(AccountStorage.accountBoxName);

      final recovered = await AccountStorage(secretStore: secretStore).open();

      expect(recovered.requiresReauthentication, isTrue);
      expect(recovered.account, isEmpty);
      expect(recovered.quarantine, isEmpty);
    },
  );

  test('missing completed account box requires reauthentication', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put('53197', _account(mid: '53197'));
    await legacy.close();

    final storage = AccountStorage(secretStore: secretStore);
    final migrated = await storage.open();
    await migrated.quarantine.close();
    await migrated.account.close();
    await Hive.deleteBoxFromDisk(AccountStorage.accountBoxName);

    final recovered = await storage.open();

    expect(recovered.requiresReauthentication, isTrue);
    expect(recovered.account, isEmpty);
    expect(recovered.quarantine, isEmpty);
  });

  test('duplicate account mids fail without deleting legacy data', () async {
    final legacy = await Hive.openBox<LoginAccount>(
      AccountStorage.legacyAccountBoxName,
    );
    await legacy.put('first', _account(mid: '11223', session: 'first'));
    await legacy.put('second', _account(mid: '11223', session: 'second'));
    await legacy.close();

    await expectLater(
      AccountStorage(secretStore: secretStore).open(),
      throwsA(
        isA<AccountStorageException>().having(
          (error) => error.code,
          'code',
          'duplicate_account_mid',
        ),
      ),
    );
    expect(
      await Hive.boxExists(AccountStorage.legacyAccountBoxName),
      isTrue,
    );
  });
}

LoginAccount _account({
  required String mid,
  String session = 'session-secret',
  String? accessKey,
}) => LoginAccount.fromCookieMap(
  {
    'SESSDATA': session,
    'DedeUserID': mid,
    'bili_jct': 'csrf-$mid',
  },
  accessKey: accessKey,
  refresh: 'refresh-$mid',
  type: <AccountType>{AccountType.main},
);

Future<List<int>> _boxBytes(Directory directory, String boxName) {
  final normalizedName = boxName.toLowerCase();
  final file = directory.listSync().whereType<File>().firstWhere(
    (file) =>
        file.path.toLowerCase().contains(normalizedName) &&
        file.path.toLowerCase().endsWith('.hive'),
  );
  return file.readAsBytes();
}

final class _MemoryAccountSecretStore implements AccountSecretStore {
  final Map<String, String> _values = {};
  String? failOnceForValue;

  void clear() => _values.clear();

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (value == failOnceForValue) {
      failOnceForValue = null;
      throw StateError('injected secure storage failure');
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
