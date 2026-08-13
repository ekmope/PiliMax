import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/pilimax/utils/android/android_mmkv_box.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

final class AndroidMmkvRecoveryException implements Exception {
  const AndroidMmkvRecoveryException(this.code);

  final String code;

  @override
  String toString() => 'AndroidMmkvRecoveryException($code)';
}

final class AndroidMmkvRecoveryBackup {
  const AndroidMmkvRecoveryBackup({
    required this.file,
    required this.sha256,
  });

  final File file;
  final String sha256;
}

final class AndroidMmkvRecoveryService {
  AndroidMmkvRecoveryService({
    required this.backupDirectory,
    required this.migrationState,
    this.store = const AndroidMmkvStore(),
    this.legacyHiveDirectory,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const int backupSchemaVersion = 1;

  final Directory backupDirectory;
  final Directory? legacyHiveDirectory;
  final AndroidMmkvMigrationStateBackend migrationState;
  final AndroidMmkvStoreBackend store;
  final DateTime Function() _now;

  Future<AndroidMmkvRecoveryBackup> backupAndReset(
    AndroidMmkvMigrationException failure,
  ) async {
    if (!failure.canReset) {
      throw const AndroidMmkvRecoveryException('reset_not_allowed');
    }
    if (!store.isAvailable) {
      throw const AndroidMmkvRecoveryException('store_unavailable');
    }

    final backup = await _createVerifiedBackup(failure);
    await _enterRecoveringState(failure.boxName);
    await _resetToEmptyMigratedBox(failure.boxName);
    return backup;
  }

  Future<void> _enterRecoveringState(String boxName) async {
    try {
      await migrationState.setState(
        boxName,
        AndroidMmkvMigrationState.recovering,
      );
    } catch (_) {
      throw const AndroidMmkvRecoveryException(
        'recovery_state_write_failed',
      );
    }
    if (migrationState.getState(boxName) !=
        AndroidMmkvMigrationState.recovering) {
      throw const AndroidMmkvRecoveryException(
        'recovery_state_write_failed',
      );
    }
    final recoveryKey = AndroidMmkvStore.recoveryKey(boxName);
    final guardWritten =
        store.putRaw(AndroidMmkvStore.metaBox, recoveryKey, '1') &&
        store.sync(AndroidMmkvStore.metaBox) &&
        store.getRaw(AndroidMmkvStore.metaBox, recoveryKey) == '1';
    if (!guardWritten) {
      throw const AndroidMmkvRecoveryException('recovery_guard_write_failed');
    }
  }

  Future<AndroidMmkvRecoveryBackup> _createVerifiedBackup(
    AndroidMmkvMigrationException failure,
  ) async {
    final boxName = failure.boxName.toLowerCase();
    final boxSnapshot = store.exportBox(boxName);
    if (boxSnapshot == null) {
      throw const AndroidMmkvRecoveryException('backup_snapshot_failed');
    }

    try {
      await backupDirectory.create(recursive: true);
    } catch (_) {
      throw const AndroidMmkvRecoveryException(
        'backup_directory_create_failed',
      );
    }

    final backupBundle = _nextBackupBundle(boxName);
    final temporaryBundle = Directory('${backupBundle.path}.tmp');
    try {
      await temporaryBundle.create();
      final legacyHive = await _copyLegacyHiveSnapshot(
        boxName,
        temporaryBundle,
      );
      final migrationKey = AndroidMmkvStore.migrationKey(boxName);
      final consistencyKey = AndroidMmkvStore.consistencyKey(boxName);
      final recoveryKey = AndroidMmkvStore.recoveryKey(boxName);
      final payload = <String, Object?>{
        'schemaVersion': backupSchemaVersion,
        'createdAtUtc': _now().toUtc().toIso8601String(),
        'boxName': boxName,
        'failure': <String, String>{
          'phase': failure.phase.name,
          'code': failure.code,
        },
        // Keep the raw JSON string intact. A corrupt value still needs to be
        // recoverable from the private backup even when it cannot be decoded.
        'boxSnapshot': boxSnapshot,
        'metadata': <String, String?>{
          migrationKey: store.getRaw(AndroidMmkvStore.metaBox, migrationKey),
          consistencyKey: store.getRaw(
            AndroidMmkvStore.metaBox,
            consistencyKey,
          ),
          AndroidMmkvMigrationState.key(boxName): migrationState.getState(
            boxName,
          ),
          recoveryKey: store.getRaw(AndroidMmkvStore.metaBox, recoveryKey),
        },
        'legacyHive': legacyHive,
      };
      final payloadJson = jsonEncode(payload);
      final digest = sha256.convert(utf8.encode(payloadJson)).toString();
      final document = jsonEncode({...payload, 'sha256': digest});
      final temporaryManifest = File(
        path.join(temporaryBundle.path, 'manifest.json'),
      );
      IOSink? sink;
      try {
        sink = temporaryManifest.openWrite(mode: FileMode.writeOnly)
          ..add(utf8.encode(document));
        await sink.flush();
        await sink.close();
        sink = null;
      } finally {
        await sink?.close();
      }
      await _validateBackup(temporaryManifest, expectedDigest: digest);
      await temporaryBundle.rename(backupBundle.path);
      final backupFile = File(path.join(backupBundle.path, 'manifest.json'));
      await _validateBackup(backupFile, expectedDigest: digest);
      return AndroidMmkvRecoveryBackup(file: backupFile, sha256: digest);
    } catch (error) {
      try {
        if (temporaryBundle.existsSync()) {
          temporaryBundle.deleteSync(recursive: true);
        }
        if (backupBundle.existsSync()) {
          backupBundle.deleteSync(recursive: true);
        }
      } catch (_) {}
      if (error is AndroidMmkvRecoveryException) rethrow;
      throw const AndroidMmkvRecoveryException('backup_write_failed');
    }
  }

  Directory _nextBackupBundle(String boxName) {
    final safeBoxName = boxName.replaceAll(RegExp('[^a-z0-9_-]'), '_');
    final timestamp = _now().toUtc().millisecondsSinceEpoch;
    var suffix = 0;
    while (true) {
      final suffixText = suffix == 0 ? '' : '-$suffix';
      final directory = Directory(
        path.join(
          backupDirectory.path,
          'mmkv-$safeBoxName-$timestamp$suffixText',
        ),
      );
      if (!directory.existsSync() &&
          !Directory('${directory.path}.tmp').existsSync()) {
        return directory;
      }
      suffix++;
    }
  }

  Future<Map<String, Object?>> _copyLegacyHiveSnapshot(
    String boxName,
    Directory targetDirectory,
  ) async {
    final hiveDirectory = legacyHiveDirectory;
    if (hiveDirectory == null) return const {'present': false};
    final files = <Map<String, Object?>>[];
    for (final extension in const ['hive', 'hivec']) {
      final source = File(
        path.join(hiveDirectory.path, '$boxName.$extension'),
      );
      if (!source.existsSync()) continue;
      files.add(
        await _copyVerifiedLegacyFile(
          source,
          File(path.join(targetDirectory.path, 'legacy.$extension')),
        ),
      );
    }
    if (files.isEmpty) return const {'present': false};
    return {'present': true, 'files': files};
  }

  Future<Map<String, Object?>> _copyVerifiedLegacyFile(
    File source,
    File target,
  ) async {
    final sourceLengthBefore = source.lengthSync();
    final sourceDigestBefore = await _fileSha256(source);
    await source.copy(target.path);
    final sourceLengthAfter = source.lengthSync();
    final sourceDigestAfter = await _fileSha256(source);
    final targetDigest = await _fileSha256(target);
    if (sourceLengthBefore != sourceLengthAfter ||
        target.lengthSync() != sourceLengthAfter ||
        sourceDigestBefore != sourceDigestAfter ||
        sourceDigestAfter != targetDigest) {
      throw const AndroidMmkvRecoveryException(
        'legacy_backup_validation_failed',
      );
    }
    return {
      'file': path.basename(target.path),
      'length': sourceLengthAfter,
      'sha256': targetDigest,
    };
  }

  static Future<String> _fileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _validateBackup(
    File file, {
    required String expectedDigest,
  }) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const AndroidMmkvRecoveryException('backup_validation_failed');
    }
    final actualDigest = decoded.remove('sha256');
    if (actualDigest is! String || actualDigest != expectedDigest) {
      throw const AndroidMmkvRecoveryException('backup_checksum_failed');
    }
    final computedDigest = sha256
        .convert(utf8.encode(jsonEncode(decoded)))
        .toString();
    if (computedDigest != expectedDigest ||
        decoded['schemaVersion'] != backupSchemaVersion ||
        decoded['boxSnapshot'] is! String) {
      throw const AndroidMmkvRecoveryException('backup_validation_failed');
    }
    final legacyHive = decoded['legacyHive'];
    if (legacyHive is! Map<String, dynamic> || legacyHive['present'] is! bool) {
      throw const AndroidMmkvRecoveryException('backup_validation_failed');
    }
    if (legacyHive['present'] as bool) {
      final files = legacyHive['files'];
      if (files is! List || files.isEmpty) {
        throw const AndroidMmkvRecoveryException(
          'legacy_backup_validation_failed',
        );
      }
      for (final entry in files) {
        if (entry is! Map<String, dynamic>) {
          throw const AndroidMmkvRecoveryException(
            'legacy_backup_validation_failed',
          );
        }
        final fileName = entry['file'];
        final length = entry['length'];
        final digest = entry['sha256'];
        if (fileName is! String ||
            path.basename(fileName) != fileName ||
            length is! int ||
            digest is! String) {
          throw const AndroidMmkvRecoveryException(
            'legacy_backup_validation_failed',
          );
        }
        final legacyFile = File(path.join(file.parent.path, fileName));
        if (!legacyFile.existsSync() ||
            legacyFile.lengthSync() != length ||
            await _fileSha256(legacyFile) != digest) {
          throw const AndroidMmkvRecoveryException(
            'legacy_backup_validation_failed',
          );
        }
      }
    }
  }

  Future<void> _resetToEmptyMigratedBox(String rawBoxName) async {
    final boxName = rawBoxName.toLowerCase();
    final migrationKey = AndroidMmkvStore.migrationKey(boxName);
    final consistencyKey = AndroidMmkvStore.consistencyKey(boxName);
    final recoveryKey = AndroidMmkvStore.recoveryKey(boxName);

    if (!store.clearBox(boxName) || !store.sync(boxName)) {
      throw const AndroidMmkvRecoveryException('box_reset_failed');
    }
    if (!_isRawBoxEmpty(store.exportBox(boxName))) {
      throw const AndroidMmkvRecoveryException('box_reset_validation_failed');
    }

    final metadataRemoved =
        store.removeRaw(AndroidMmkvStore.metaBox, migrationKey) &&
        store.removeRaw(AndroidMmkvStore.metaBox, consistencyKey) &&
        store.sync(AndroidMmkvStore.metaBox) &&
        store.getRaw(AndroidMmkvStore.metaBox, migrationKey) == null &&
        store.getRaw(AndroidMmkvStore.metaBox, consistencyKey) == null;
    if (!metadataRemoved) {
      throw const AndroidMmkvRecoveryException('metadata_reset_failed');
    }

    final consistencyToken = AndroidMmkvStore.newConsistencyToken();
    final sentinelWritten =
        store.putRaw(
          boxName,
          AndroidMmkvStore.consistencySentinelKey,
          consistencyToken,
        ) &&
        store.sync(boxName) &&
        store.getRaw(boxName, AndroidMmkvStore.consistencySentinelKey) ==
            consistencyToken;
    if (!sentinelWritten) {
      throw const AndroidMmkvRecoveryException('sentinel_write_failed');
    }

    final metadataWritten =
        store.putRaw(
          AndroidMmkvStore.metaBox,
          consistencyKey,
          consistencyToken,
        ) &&
        store.putRaw(AndroidMmkvStore.metaBox, migrationKey, '1') &&
        store.sync(AndroidMmkvStore.metaBox) &&
        store.getRaw(AndroidMmkvStore.metaBox, consistencyKey) ==
            consistencyToken &&
        store.getRaw(AndroidMmkvStore.metaBox, migrationKey) == '1';
    if (!metadataWritten) {
      throw const AndroidMmkvRecoveryException('metadata_write_failed');
    }

    try {
      await migrationState.setState(
        boxName,
        AndroidMmkvMigrationState.complete,
      );
    } catch (_) {
      if (migrationState.getState(boxName) !=
              AndroidMmkvMigrationState.complete ||
          !_isFreshEmptyBox(store.exportBox(boxName), consistencyToken)) {
        await _ensureFailClosed(boxName, recoveryKey);
        throw const AndroidMmkvRecoveryException('state_write_failed');
      }
    }
    if (migrationState.getState(boxName) !=
            AndroidMmkvMigrationState.complete ||
        !_isFreshEmptyBox(store.exportBox(boxName), consistencyToken)) {
      await _ensureFailClosed(boxName, recoveryKey);
      throw const AndroidMmkvRecoveryException('reset_validation_failed');
    }
    final guardRemoved =
        store.removeRaw(AndroidMmkvStore.metaBox, recoveryKey) &&
        store.sync(AndroidMmkvStore.metaBox) &&
        store.getRaw(AndroidMmkvStore.metaBox, recoveryKey) == null;
    if (!guardRemoved) {
      await _ensureFailClosed(boxName, recoveryKey);
      throw const AndroidMmkvRecoveryException('recovery_guard_clear_failed');
    }
  }

  Future<void> _ensureFailClosed(String boxName, String recoveryKey) async {
    try {
      await migrationState.setState(
        boxName,
        AndroidMmkvMigrationState.recovering,
      );
    } catch (_) {}
    if (migrationState.getState(boxName) ==
        AndroidMmkvMigrationState.recovering) {
      return;
    }
    if (store.getRaw(AndroidMmkvStore.metaBox, recoveryKey) != null) return;
    final guardWritten =
        store.putRaw(AndroidMmkvStore.metaBox, recoveryKey, '1') &&
        store.sync(AndroidMmkvStore.metaBox) &&
        store.getRaw(AndroidMmkvStore.metaBox, recoveryKey) == '1';
    if (!guardWritten) {
      throw const AndroidMmkvRecoveryException(
        'recovery_fail_closed_guard_failed',
      );
    }
  }

  static bool _isRawBoxEmpty(String? snapshot) {
    if (snapshot == null) return false;
    try {
      final decoded = jsonDecode(snapshot);
      return decoded is Map && decoded.isEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool _isFreshEmptyBox(String? snapshot, String token) {
    if (snapshot == null) return false;
    try {
      final decoded = jsonDecode(snapshot);
      return decoded is Map &&
          decoded.length == 1 &&
          decoded[AndroidMmkvStore.consistencySentinelKey] == token;
    } catch (_) {
      return false;
    }
  }
}
