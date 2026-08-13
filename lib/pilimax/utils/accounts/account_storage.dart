import 'dart:convert';
import 'dart:math';

import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

abstract interface class AccountSecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class PlatformAccountSecretStore implements AccountSecretStore {
  final FlutterSecureStorage _storage;

  const PlatformAccountSecretStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final class AccountStorageException implements Exception {
  final String code;

  const AccountStorageException(this.code);

  @override
  String toString() => 'AccountStorageException($code)';
}

final class AccountStorageOpenResult {
  final Box<LoginAccount> account;
  final Box<LoginAccount> quarantine;
  final bool requiresReauthentication;

  const AccountStorageOpenResult({
    required this.account,
    required this.quarantine,
    required this.requiresReauthentication,
  });
}

final class AccountStorage {
  static const accountBoxName = 'accountSecureV1';
  static const quarantineBoxName = 'accountQuarantineSecureV1';
  static const legacyAccountBoxName = 'account';
  static const legacyQuarantineBoxName = 'accountQuarantine';

  static const _encryptionKeyName = 'pilimax.account.hive.key.v1';
  static const _migrationStateName = 'pilimax.account.hive.migration.v1';
  static const _migrationManifestName =
      'pilimax.account.hive.migration.manifest.v1';
  static const _reauthenticationName =
      'pilimax.account.reauthentication-required.v1';

  static const _pending = 'pending';
  static const _verified = 'verified';
  static const _complete = 'complete';

  final AccountSecretStore _secretStore;
  final HiveInterface _hive;
  final Random _secureRandom;

  AccountStorage({
    AccountSecretStore? secretStore,
    HiveInterface? hive,
    Random? secureRandom,
  }) : _secretStore = secretStore ?? const PlatformAccountSecretStore(),
       _hive = hive ?? Hive,
       _secureRandom = secureRandom ?? Random.secure();

  Future<AccountStorageOpenResult> open() async {
    try {
      return await _open();
    } on AccountStorageException {
      rethrow;
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AccountStorageException('account_storage_operation_failed'),
        stackTrace,
      );
    }
  }

  Future<void> markReauthenticated() => _deleteSecret(_reauthenticationName);

  Future<AccountStorageOpenResult> _open() async {
    final legacyAccountExists = await _hive.boxExists(
      legacyAccountBoxName,
    );
    final legacyQuarantineExists = await _hive.boxExists(
      legacyQuarantineBoxName,
    );
    final secureAccountExists = await _hive.boxExists(accountBoxName);
    final secureQuarantineExists = await _hive.boxExists(quarantineBoxName);
    final secureBoxesExist = secureAccountExists || secureQuarantineExists;

    final encodedKey = await _readSecret(_encryptionKeyName);
    final key = _decodeKey(encodedKey);
    if (key == null) {
      if (legacyAccountExists || legacyQuarantineExists) {
        final newKey = await _createAndStoreKey();
        return _migrateLegacy(newKey);
      }
      if (secureBoxesExist) {
        return _resetAfterKeyLoss();
      }
      final newKey = await _createAndStoreKey();
      return _openFresh(newKey);
    }

    final state = await _readSecret(_migrationStateName);
    final requiresReauthentication =
        await _readSecret(_reauthenticationName) == 'true';

    if (state == _verified) {
      if (!secureAccountExists || !secureQuarantineExists) {
        if (legacyAccountExists || legacyQuarantineExists) {
          return _migrateLegacy(key);
        }
        return _resetWithKey(key);
      }
      return _resumeVerifiedMigration(
        key,
        requiresReauthentication: requiresReauthentication,
      );
    }

    if (state == _complete && !secureAccountExists && secureQuarantineExists) {
      if (legacyAccountExists || legacyQuarantineExists) {
        return _migrateLegacy(key);
      }
      return _resetWithKey(key);
    }

    if (state == _complete && secureAccountExists) {
      final boxes = await _openSecureBoxes(key);
      try {
        _validateActiveRecords(boxes.account.toMap());
        await _deleteLegacyBoxes();
        await _deleteSecret(_migrationManifestName);
        return AccountStorageOpenResult(
          account: boxes.account,
          quarantine: boxes.quarantine,
          requiresReauthentication: requiresReauthentication,
        );
      } catch (_) {
        await _closeSecureBoxes(boxes);
        rethrow;
      }
    }

    if (legacyAccountExists || legacyQuarantineExists) {
      return _migrateLegacy(key);
    }

    if (secureBoxesExist && state == _pending) {
      return _resetWithKey(key);
    }

    if (secureBoxesExist) {
      final boxes = await _openSecureBoxes(key);
      try {
        _validateActiveRecords(boxes.account.toMap());
        await _writeVerifiedSecret(_migrationStateName, _complete);
        await _deleteSecret(_migrationManifestName);
        return AccountStorageOpenResult(
          account: boxes.account,
          quarantine: boxes.quarantine,
          requiresReauthentication: requiresReauthentication,
        );
      } catch (_) {
        await _closeSecureBoxes(boxes);
        rethrow;
      }
    }

    return _openFresh(
      key,
      requiresReauthentication: requiresReauthentication,
    );
  }

  Future<AccountStorageOpenResult> _migrateLegacy(List<int> key) async {
    await _writeVerifiedSecret(_migrationStateName, _pending);
    await _deleteBox(accountBoxName);
    await _deleteBox(quarantineBoxName);

    Box<LoginAccount>? legacyAccount;
    Box<LoginAccount>? legacyQuarantine;
    _SecureBoxes? secureBoxes;
    var keepSecureBoxesOpen = false;
    try {
      if (await _hive.boxExists(legacyAccountBoxName)) {
        legacyAccount = await _openPlaintextBox(legacyAccountBoxName);
      }
      if (await _hive.boxExists(legacyQuarantineBoxName)) {
        legacyQuarantine = await _openPlaintextBox(
          legacyQuarantineBoxName,
        );
      }

      final migrationData = _buildMigrationData(
        legacyAccount?.toMap() ?? const <dynamic, LoginAccount>{},
        legacyQuarantine?.toMap() ?? const <dynamic, LoginAccount>{},
      );
      final expectedManifest = _createManifest(
        migrationData.account,
        migrationData.quarantine,
      );

      secureBoxes = await _openSecureBoxes(key);
      await secureBoxes.account.putAll(migrationData.account);
      await secureBoxes.quarantine.putAll(migrationData.quarantine);
      await _closeSecureBoxes(secureBoxes);
      secureBoxes = await _openSecureBoxes(key);

      final actualManifest = _createManifest(
        secureBoxes.account.toMap(),
        secureBoxes.quarantine.toMap(),
      );
      _verifyManifest(expectedManifest, actualManifest);

      await _writeVerifiedSecret(
        _migrationManifestName,
        expectedManifest.encode(),
      );
      await _writeVerifiedSecret(_migrationStateName, _verified);

      await legacyQuarantine?.close();
      legacyQuarantine = null;
      await legacyAccount?.close();
      legacyAccount = null;
      await _deleteLegacyBoxes();

      await _writeVerifiedSecret(_migrationStateName, _complete);
      await _deleteSecret(_migrationManifestName);
      await _deleteSecret(_reauthenticationName);

      keepSecureBoxesOpen = true;
      return AccountStorageOpenResult(
        account: secureBoxes.account,
        quarantine: secureBoxes.quarantine,
        requiresReauthentication: false,
      );
    } finally {
      await _closeBoxQuietly(legacyQuarantine);
      await _closeBoxQuietly(legacyAccount);
      if (!keepSecureBoxesOpen && secureBoxes != null) {
        await _closeSecureBoxes(secureBoxes);
      }
    }
  }

  Future<AccountStorageOpenResult> _resumeVerifiedMigration(
    List<int> key, {
    required bool requiresReauthentication,
  }) async {
    final encodedManifest = await _readSecret(_migrationManifestName);
    final expectedManifest = _MigrationManifest.decode(encodedManifest);
    final boxes = await _openSecureBoxes(key);
    try {
      final actualManifest = _createManifest(
        boxes.account.toMap(),
        boxes.quarantine.toMap(),
      );
      _verifyManifest(expectedManifest, actualManifest);
      await _deleteLegacyBoxes();
      await _writeVerifiedSecret(_migrationStateName, _complete);
      await _deleteSecret(_migrationManifestName);
      return AccountStorageOpenResult(
        account: boxes.account,
        quarantine: boxes.quarantine,
        requiresReauthentication: requiresReauthentication,
      );
    } catch (_) {
      await _closeSecureBoxes(boxes);
      rethrow;
    }
  }

  Future<AccountStorageOpenResult> _resetAfterKeyLoss() async {
    await _writeVerifiedSecret(_reauthenticationName, 'true');
    await _deleteAllAccountBoxes();
    await _deleteSecret(_migrationManifestName);
    final key = await _createAndStoreKey();
    return _openFresh(key, requiresReauthentication: true);
  }

  Future<AccountStorageOpenResult> _resetWithKey(List<int> key) async {
    await _writeVerifiedSecret(_reauthenticationName, 'true');
    await _deleteAllAccountBoxes();
    await _deleteSecret(_migrationManifestName);
    return _openFresh(key, requiresReauthentication: true);
  }

  Future<AccountStorageOpenResult> _openFresh(
    List<int> key, {
    bool requiresReauthentication = false,
  }) async {
    final boxes = await _openSecureBoxes(key);
    try {
      if (boxes.account.isNotEmpty || boxes.quarantine.isNotEmpty) {
        throw const AccountStorageException('fresh_boxes_not_empty');
      }
      await _writeVerifiedSecret(_migrationStateName, _complete);
      await _deleteSecret(_migrationManifestName);
      return AccountStorageOpenResult(
        account: boxes.account,
        quarantine: boxes.quarantine,
        requiresReauthentication: requiresReauthentication,
      );
    } catch (_) {
      await _closeSecureBoxes(boxes);
      rethrow;
    }
  }

  Future<List<int>> _createAndStoreKey() async {
    final key = List<int>.generate(
      32,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    await _writeVerifiedSecret(_encryptionKeyName, base64UrlEncode(key));
    return key;
  }

  List<int>? _decodeKey(String? encodedKey) {
    if (encodedKey == null) return null;
    try {
      final key = base64Url.decode(encodedKey);
      if (key.length != 32) return null;
      return List<int>.unmodifiable(key);
    } catch (_) {
      return null;
    }
  }

  Future<_SecureBoxes> _openSecureBoxes(List<int> key) async {
    Box<LoginAccount>? account;
    Box<LoginAccount>? quarantine;
    try {
      final cipher = HiveAesCipher(key);
      account = await _hive.openBox<LoginAccount>(
        accountBoxName,
        encryptionCipher: cipher,
        compactionStrategy: _compactAccounts,
      );
      quarantine = await _hive.openBox<LoginAccount>(
        quarantineBoxName,
        encryptionCipher: cipher,
        compactionStrategy: _compactAccounts,
      );
      return (account: account, quarantine: quarantine);
    } catch (_) {
      await _closeBoxQuietly(quarantine);
      await _closeBoxQuietly(account);
      rethrow;
    }
  }

  Future<Box<LoginAccount>> _openPlaintextBox(String name) =>
      _hive.openBox<LoginAccount>(
        name,
        compactionStrategy: _compactAccounts,
      );

  static bool _compactAccounts(int entries, int deletedEntries) =>
      deletedEntries > 2;

  _MigrationData _buildMigrationData(
    Map<dynamic, LoginAccount> sourceAccounts,
    Map<dynamic, LoginAccount> sourceQuarantine,
  ) {
    final accounts = <dynamic, LoginAccount>{};
    final quarantine = <dynamic, LoginAccount>{};

    for (final entry in sourceQuarantine.entries) {
      _addToQuarantine(quarantine, entry.key, entry.value);
    }
    for (final entry in sourceAccounts.entries) {
      final account = entry.value;
      if (!account.isValid) {
        _addToQuarantine(quarantine, entry.key, account);
        continue;
      }
      final key = account.mid.toString();
      if (accounts.containsKey(key)) {
        throw const AccountStorageException('duplicate_account_mid');
      }
      accounts[key] = account;
    }
    return (account: accounts, quarantine: quarantine);
  }

  void _addToQuarantine(
    Map<dynamic, LoginAccount> quarantine,
    dynamic sourceKey,
    LoginAccount account,
  ) {
    dynamic key = sourceKey is int || sourceKey is String
        ? sourceKey
        : 'invalid-key';
    if (!quarantine.containsKey(key)) {
      quarantine[key] = account;
      return;
    }

    final prefix = 'legacy-${_canonicalKey(key)}';
    var suffix = 1;
    while (quarantine.containsKey('$prefix-$suffix')) {
      suffix++;
    }
    quarantine['$prefix-$suffix'] = account;
  }

  _MigrationManifest _createManifest(
    Map<dynamic, LoginAccount> accounts,
    Map<dynamic, LoginAccount> quarantine,
  ) {
    _validateActiveRecords(accounts);
    final mids = accounts.values.map((account) => account.mid).toList()..sort();
    final canonicalData = {
      'accounts': _canonicalRecords(accounts),
      'quarantine': _canonicalRecords(quarantine),
    };
    return _MigrationManifest(
      accountCount: accounts.length,
      quarantineCount: quarantine.length,
      mids: mids,
      digest: sha256.convert(utf8.encode(jsonEncode(canonicalData))).toString(),
    );
  }

  void _validateActiveRecords(Map<dynamic, LoginAccount> accounts) {
    for (final entry in accounts.entries) {
      if (!entry.value.isValid) {
        throw const AccountStorageException('active_account_invalid');
      }
      if (entry.key != entry.value.mid.toString()) {
        throw const AccountStorageException('active_account_mid_mismatch');
      }
    }
  }

  List<Map<String, Object?>> _canonicalRecords(
    Map<dynamic, LoginAccount> accounts,
  ) {
    final records = accounts.entries.map((entry) {
      final account = entry.value;
      final cookies = account.cookieJar.toJson().entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final types = account.type.map((type) => type.index).toList()..sort();
      return <String, Object?>{
        'key': _canonicalKey(entry.key),
        'valid': account.isValid,
        'mid': account.isValid ? account.mid : null,
        'cookies': [
          for (final cookie in cookies) [cookie.key, cookie.value],
        ],
        'accessKey': account.accessKey,
        'refresh': account.refresh,
        'types': types,
        'validationIssue': account.validationIssue?.name,
      };
    }).toList();
    return records..sort(
      (a, b) => (a['key']! as String).compareTo(b['key']! as String),
    );
  }

  String _canonicalKey(dynamic key) => switch (key) {
    int value => 'int:$value',
    String value => 'string:$value',
    _ => throw const AccountStorageException('unsupported_account_key'),
  };

  void _verifyManifest(
    _MigrationManifest expected,
    _MigrationManifest actual,
  ) {
    if (actual.accountCount != expected.accountCount ||
        actual.quarantineCount != expected.quarantineCount) {
      throw const AccountStorageException('account_count_mismatch');
    }
    if (!_sameInts(actual.mids, expected.mids)) {
      throw const AccountStorageException('account_mid_mismatch');
    }
    if (actual.digest != expected.digest) {
      throw const AccountStorageException('account_cookie_integrity_mismatch');
    }
  }

  bool _sameInts(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> _deleteLegacyBoxes() async {
    await _deleteBox(legacyQuarantineBoxName);
    await _deleteBox(legacyAccountBoxName);
  }

  Future<void> _deleteAllAccountBoxes() async {
    await _deleteBox(quarantineBoxName);
    await _deleteBox(accountBoxName);
    await _deleteLegacyBoxes();
  }

  Future<void> _deleteBox(String name) async {
    if (_hive.isBoxOpen(name)) {
      await _hive.box(name).close();
    }
    if (await _hive.boxExists(name)) {
      await _hive.deleteBoxFromDisk(name);
    }
  }

  Future<String?> _readSecret(String key) async {
    try {
      return await _secretStore.read(key);
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AccountStorageException('secure_storage_read_failed'),
        stackTrace,
      );
    }
  }

  Future<void> _writeVerifiedSecret(String key, String value) async {
    try {
      await _secretStore.write(key, value);
      if (await _secretStore.read(key) != value) {
        throw const AccountStorageException('secure_storage_verify_failed');
      }
    } on AccountStorageException {
      rethrow;
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AccountStorageException('secure_storage_write_failed'),
        stackTrace,
      );
    }
  }

  Future<void> _deleteSecret(String key) async {
    try {
      await _secretStore.delete(key);
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AccountStorageException('secure_storage_delete_failed'),
        stackTrace,
      );
    }
  }

  Future<void> _closeSecureBoxes(_SecureBoxes boxes) async {
    await _closeBoxQuietly(boxes.quarantine);
    await _closeBoxQuietly(boxes.account);
  }

  Future<void> _closeBoxQuietly(BoxBase? box) async {
    if (box == null || !box.isOpen) return;
    try {
      await box.close();
    } catch (_) {}
  }
}

final class _MigrationManifest {
  static const _version = 1;

  final int accountCount;
  final int quarantineCount;
  final List<int> mids;
  final String digest;

  const _MigrationManifest({
    required this.accountCount,
    required this.quarantineCount,
    required this.mids,
    required this.digest,
  });

  String encode() => jsonEncode({
    'version': _version,
    'accountCount': accountCount,
    'quarantineCount': quarantineCount,
    'mids': mids,
    'digest': digest,
  });

  factory _MigrationManifest.decode(String? value) {
    try {
      final data = jsonDecode(value!);
      if (data is! Map ||
          data['version'] != _version ||
          data['accountCount'] is! int ||
          data['quarantineCount'] is! int ||
          data['mids'] is! List ||
          data['digest'] is! String) {
        throw const FormatException();
      }
      final mids = (data['mids'] as List).whereType<int>().toList();
      if (mids.length != (data['mids'] as List).length ||
          (data['accountCount'] as int) < 0 ||
          (data['quarantineCount'] as int) < 0 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(data['digest'] as String)) {
        throw const FormatException();
      }
      return _MigrationManifest(
        accountCount: data['accountCount'] as int,
        quarantineCount: data['quarantineCount'] as int,
        mids: mids,
        digest: data['digest'] as String,
      );
    } catch (_) {
      throw const AccountStorageException('migration_manifest_invalid');
    }
  }
}

typedef _SecureBoxes = ({
  Box<LoginAccount> account,
  Box<LoginAccount> quarantine,
});

typedef _MigrationData = ({
  Map<dynamic, LoginAccount> account,
  Map<dynamic, LoginAccount> quarantine,
});
