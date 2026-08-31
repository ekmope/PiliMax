import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show loadFontFromList;

import 'package:PiliMax/pilimax/utils/font_name_parser.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

typedef CustomFontLoaderCallback = Future<void> Function({
  required String fontPath,
  required String fontFamily,
});

final class CustomFontStorageKeys {
  const CustomFontStorageKeys({
    required this.path,
    required this.family,
    required this.name,
  }) : assert(path != family),
       assert(path != name),
       assert(family != name);

  final String path;
  final String family;
  final String name;

  List<String> get all => [path, family, name];
}

final class CustomFontSelectionBinding {
  const CustomFontSelectionBinding({
    required this.selectionKey,
    this.fallbackValues = const {},
    this.fallbackDeletes = const {},
  });

  final String selectionKey;
  final Map<String, Object?> fallbackValues;
  final Set<String> fallbackDeletes;
}

final class CustomFontConfig {
  const CustomFontConfig({
    required this.directoryName,
    required this.fileNamePrefix,
    required this.familyNamePrefix,
    required this.libraryPathKey,
    required this.libraryNameKey,
    this.selectionBindings = const [],
  }) : assert(directoryName != ''),
       assert(fileNamePrefix != ''),
       assert(familyNamePrefix != ''),
       assert(libraryPathKey != libraryNameKey);

  final String directoryName;
  final String fileNamePrefix;
  final String familyNamePrefix;
  final String libraryPathKey;
  final String libraryNameKey;
  final List<CustomFontSelectionBinding> selectionBindings;
}

final class LegacyCustomFontMigration {
  const LegacyCustomFontMigration({
    required this.directoryName,
    required this.fileNamePrefix,
    required this.storageKeys,
    required this.selectionKey,
  });

  final String directoryName;
  final String fileNamePrefix;
  final CustomFontStorageKeys storageKeys;
  final String selectionKey;
}

final class CustomFontEntry {
  const CustomFontEntry({
    required this.fontPath,
    required this.fontFamily,
    required this.displayName,
  });

  final String fontPath;
  final String fontFamily;
  final String displayName;
}

final class CustomFontSelection {
  const CustomFontSelection({
    required this.fontPath,
    required this.fontFamily,
    required this.displayName,
  });

  final String? fontPath;
  final String? fontFamily;
  final String? displayName;

  bool get isComplete => fontPath != null && fontFamily != null;
}

final class CustomFontImportResult {
  const CustomFontImportResult({
    required this.fonts,
    required this.failedCount,
  });

  final List<CustomFontEntry> fonts;
  final int failedCount;
}

sealed class CustomFontSource {
  const CustomFontSource({
    required this.sourceName,
    this.preferredDisplayName,
  }) : assert(sourceName != '');

  final String sourceName;
  final String? preferredDisplayName;

  String get displayName {
    final preferred = preferredDisplayName?.trim();
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final fromFile = path.basenameWithoutExtension(sourceName).trim();
    return fromFile.isEmpty ? '未命名字体' : fromFile;
  }
}

final class CustomFontBytesSource extends CustomFontSource {
  const CustomFontBytesSource({
    required super.sourceName,
    super.preferredDisplayName,
    required this.bytes,
  });

  final Uint8List bytes;
}

final class CustomFontFileSource extends CustomFontSource {
  const CustomFontFileSource({
    required this.sourcePath,
    super.preferredDisplayName,
  }) : super(sourceName: sourcePath);

  final String sourcePath;
}

abstract interface class CustomFontSettingsStore {
  bool containsKey(String key);

  Object? read(String key);

  Future<void> putAll(Map<String, Object?> values);

  Future<void> deleteAll(Iterable<String> keys);
}

final class CustomFontSettingsException implements Exception {
  const CustomFontSettingsException({
    required this.operationError,
    required this.rollbackError,
  });

  final Object operationError;
  final Object rollbackError;

  @override
  String toString() =>
      'Custom font settings update failed ($operationError); '
      'rollback also failed ($rollbackError).';
}

/// Shared persistent font pool used by App and danmaku font selections.
final class CustomFontManager {
  CustomFontManager({
    required this.config,
    required this.settingsStore,
    CustomFontLoaderCallback? fontLoader,
    String Function()? supportDirectory,
    int Function()? nowMicroseconds,
  }) : _fontLoader = fontLoader ?? _loadFont,
       _supportDirectory = supportDirectory ?? (() => appSupportDirPath),
       _nowMicroseconds =
           nowMicroseconds ?? (() => DateTime.now().microsecondsSinceEpoch);

  static const List<String> allowedExtensions = ['ttf', 'otf', 'ttc'];
  static final RegExp _managedHash = RegExp(r'^[0-9a-f]{40}$');
  static final RegExp _legacyId = RegExp(r'^\d+$');

  final CustomFontConfig config;
  final CustomFontSettingsStore settingsStore;
  final CustomFontLoaderCallback _fontLoader;
  final String Function() _supportDirectory;
  final int Function() _nowMicroseconds;
  final Lock _operationLock = Lock();
  final Set<String> _loadedFamilies = {};
  final Map<String, Future<void>> _loadingFamilies = {};

  Map<String, String>? _fontPathsCache;
  Map<String, String>? _fontNamesCache;
  bool _initialized = false;

  Map<String, String> get _fontPaths =>
      _fontPathsCache ??= _readStringMap(config.libraryPathKey);

  Map<String, String> get _fontNames =>
      _fontNamesCache ??= _readStringMap(config.libraryNameKey);

  Directory get _fontDirectory => Directory(
    path.join(_supportDirectory(), config.directoryName),
  );

  List<CustomFontEntry> get fonts {
    final result = <CustomFontEntry>[
      for (final entry in _fontPaths.entries)
        CustomFontEntry(
          fontPath: entry.value,
          fontFamily: entry.key,
          displayName: _fontNames[entry.key] ?? entry.key,
        ),
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return List.unmodifiable(result);
  }

  bool isCustomFont(String? fontFamily) =>
      fontFamily != null && _fontPaths.containsKey(fontFamily);

  String displayName(String fontFamily) => _fontNames[fontFamily] ?? fontFamily;

  CustomFontSelection selectionFor(String? fontFamily) {
    final fontPath = fontFamily == null ? null : _fontPaths[fontFamily];
    return CustomFontSelection(
      fontPath: fontPath,
      fontFamily: fontPath == null ? null : fontFamily,
      displayName: fontPath == null
          ? null
          : (_fontNames[fontFamily] ?? fontFamily),
    );
  }

  /// Repairs the pool without allowing a bad font to block app startup.
  Future<void> init({
    Iterable<LegacyCustomFontMigration> migrations = const [],
    Iterable<String?> activeFamilies = const [],
  }) async {
    try {
      await _operationLock.synchronized(() async {
        if (!_initialized) {
          for (final migration in migrations) {
            await _migrateLegacyFont(migration);
          }
          await _pruneInvalidEntries();
          await _cleanupOrphanFiles();
          _initialized = true;
        }
        for (final family in activeFamilies) {
          if (isCustomFont(family)) {
            try {
              await _ensureLoaded(
                family!,
              ).timeout(const Duration(seconds: 2));
            } catch (_) {}
          }
        }
      });
    } catch (error) {
      debugPrint('custom font initialization failed: $error');
    }
  }

  Future<CustomFontImportResult> importFonts(
    Iterable<CustomFontSource> sources,
  ) => _operationLock.synchronized(() async {
    final imported = <CustomFontEntry>[];
    var failedCount = 0;
    for (final source in sources) {
      try {
        imported.add(await _importFont(source));
      } catch (_) {
        failedCount++;
      }
    }
    return CustomFontImportResult(
      fonts: List.unmodifiable(imported),
      failedCount: failedCount,
    );
  });

  Future<CustomFontEntry> importFont(CustomFontSource source) =>
      _operationLock.synchronized(() => _importFont(source));

  /// Selects an existing pool entry transactionally, without another copy.
  Future<void> selectExisting({
    required String fontFamily,
    required String selectionKey,
    Iterable<String> deleteKeys = const [],
    Map<String, Object?> additionalValues = const {},
  }) => _operationLock.synchronized(() async {
    if (!isCustomFont(fontFamily)) {
      throw StateError('font is not in the managed library');
    }
    await _ensureLoaded(fontFamily).timeout(const Duration(seconds: 5));
    await _replaceSettings(
      values: {...additionalValues, selectionKey: fontFamily},
      deleteKeys: deleteKeys,
    );
  });

  Future<void> selectValue({
    required String selectionKey,
    required String? fontFamily,
    Iterable<String> deleteKeys = const [],
    Map<String, Object?> additionalValues = const {},
  }) => _operationLock.synchronized(() async {
    if (isCustomFont(fontFamily)) {
      await _ensureLoaded(fontFamily!).timeout(const Duration(seconds: 5));
    }
    final values = <String, Object?>{...additionalValues};
    final deletes = <String>{...deleteKeys};
    if (fontFamily == null) {
      deletes.add(selectionKey);
    } else {
      values[selectionKey] = fontFamily;
    }
    await _replaceSettings(values: values, deleteKeys: deletes);
  });

  Future<void> ensureLoaded(String fontFamily) =>
      _operationLock.synchronized(() => _ensureLoaded(fontFamily));

  Future<void> removeFont(String fontFamily) =>
      _operationLock.synchronized(() async {
        final filePath = _fontPaths[fontFamily];
        if (filePath == null) return;

        final nextPaths = Map<String, String>.of(_fontPaths)
          ..remove(fontFamily);
        final nextNames = Map<String, String>.of(_fontNames)
          ..remove(fontFamily);
        final values = <String, Object?>{
          config.libraryPathKey: nextPaths,
          config.libraryNameKey: nextNames,
        };
        final deletes = <String>{};
        _addSelectionFallbacks({fontFamily}, values, deletes);
        await _replaceSettings(values: values, deleteKeys: deletes);

        _fontPathsCache = nextPaths;
        _fontNamesCache = nextNames;
        _loadedFamilies.remove(fontFamily);
        if (_isManagedFile(File(filePath), _fontDirectory)) {
          await _deleteBestEffort(File(filePath));
        }
      });

  Future<void> clearFonts() => _operationLock.synchronized(() async {
    final removed = _fontPaths.keys.toSet();
    if (removed.isEmpty) return;

    final values = <String, Object?>{
      config.libraryPathKey: const <String, String>{},
      config.libraryNameKey: const <String, String>{},
    };
    final deletes = <String>{};
    _addSelectionFallbacks(removed, values, deletes);
    await _replaceSettings(values: values, deleteKeys: deletes);

    _fontPathsCache = {};
    _fontNamesCache = {};
    _loadedFamilies.clear();
    await _cleanupManagedFiles();
  });

  Future<CustomFontEntry> _importFont(CustomFontSource source) async {
    final extension = _extensionOf(source.sourceName);
    if (extension == null) {
      throw UnsupportedError(
        'unsupported font file: ${path.extension(source.sourceName)}',
      );
    }

    final fontDir = _fontDirectory;
    if (!fontDir.existsSync()) {
      await fontDir.create(recursive: true);
    }
    final temporaryFile = File(
      path.join(
        fontDir.path,
        '.${config.fileNamePrefix}_importing_${_nowMicroseconds()}',
      ),
    );

    File? targetFile;
    var createdTarget = false;
    try {
      await _copySource(source, temporaryFile);
      if (!temporaryFile.existsSync() || await temporaryFile.length() == 0) {
        throw StateError('font file is empty');
      }

      final digest = await _hashFile(temporaryFile);
      final hash = digest;
      final fontFamily = '${config.familyNamePrefix}_$hash';
      final metadata = await FontNameParser.inspect(temporaryFile.path);
      if (metadata == null) {
        throw const FormatException('invalid font file');
      }
      final displayName = metadata.displayName ?? source.displayName;

      final existingPath = _fontPaths[fontFamily];
      if (existingPath != null &&
          _isManagedEntry(fontFamily, File(existingPath), fontDir) &&
          File(existingPath).existsSync()) {
        if (await _tryHashFile(File(existingPath)) != digest) {
          throw StateError('managed font content does not match its SHA-1');
        }
        await _ensureLoadedFromFile(
          fontFamily: fontFamily,
          fontPath: existingPath,
        ).timeout(const Duration(seconds: 5));
        await _deleteBestEffort(temporaryFile);
        if (_fontNames[fontFamily] != displayName) {
          final nextNames = Map<String, String>.of(_fontNames)
            ..[fontFamily] = displayName;
          await _replaceSettings(
            values: {
              config.libraryPathKey: Map<String, String>.of(_fontPaths),
              config.libraryNameKey: nextNames,
            },
          );
          _fontNamesCache = nextNames;
        }
        return CustomFontEntry(
          fontPath: existingPath,
          fontFamily: fontFamily,
          displayName: displayName,
        );
      }

      targetFile = File(
        path.join(fontDir.path, '${config.fileNamePrefix}_$hash.$extension'),
      );
      if (targetFile.existsSync()) {
        final targetHash = await _tryHashFile(targetFile);
        if (targetHash == digest) {
          await _deleteBestEffort(temporaryFile);
        } else {
          await _deleteBestEffort(targetFile);
          await temporaryFile.rename(targetFile.path);
          createdTarget = true;
        }
      } else {
        await temporaryFile.rename(targetFile.path);
        createdTarget = true;
      }

      await _ensureLoadedFromFile(
        fontFamily: fontFamily,
        fontPath: targetFile.path,
      ).timeout(const Duration(seconds: 5));

      final nextPaths = Map<String, String>.of(_fontPaths)
        ..[fontFamily] = targetFile.path;
      final nextNames = Map<String, String>.of(_fontNames)
        ..[fontFamily] = displayName;
      await _replaceSettings(
        values: {
          config.libraryPathKey: nextPaths,
          config.libraryNameKey: nextNames,
        },
      );
      _fontPathsCache = nextPaths;
      _fontNamesCache = nextNames;

      return CustomFontEntry(
        fontPath: targetFile.path,
        fontFamily: fontFamily,
        displayName: displayName,
      );
    } catch (error, stackTrace) {
      await _deleteBestEffort(temporaryFile);
      if (createdTarget &&
          targetFile != null &&
          error is! CustomFontSettingsException) {
        await _deleteBestEffort(targetFile);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _copySource(
    CustomFontSource source,
    File targetFile,
  ) async {
    switch (source) {
      case CustomFontBytesSource(:final bytes):
        await targetFile.writeAsBytes(bytes, flush: true);
      case CustomFontFileSource(:final sourcePath):
        final sourceFile = File(sourcePath);
        if (!sourceFile.existsSync()) {
          throw StateError('font source file does not exist');
        }
        await sourceFile.copy(targetFile.path);
    }
  }

  Future<void> _ensureLoaded(String fontFamily) async {
    if (_loadedFamilies.contains(fontFamily)) return;
    final existing = _loadingFamilies[fontFamily];
    if (existing != null) return existing;

    final fontPath = _fontPaths[fontFamily];
    if (fontPath == null ||
        !_isManagedEntry(fontFamily, File(fontPath), _fontDirectory) ||
        !File(fontPath).existsSync()) {
      throw StateError('managed font file is unavailable');
    }
    return _ensureLoadedFromFile(
      fontFamily: fontFamily,
      fontPath: fontPath,
    );
  }

  Future<void> _ensureLoadedFromFile({
    required String fontFamily,
    required String fontPath,
  }) async {
    if (_loadedFamilies.contains(fontFamily)) return;
    final existing = _loadingFamilies[fontFamily];
    if (existing != null) return existing;

    final loading = () async {
      await _fontLoader(fontPath: fontPath, fontFamily: fontFamily);
      _loadedFamilies.add(fontFamily);
    }();
    _loadingFamilies[fontFamily] = loading;
    try {
      await loading;
    } finally {
      if (identical(_loadingFamilies[fontFamily], loading)) {
        _loadingFamilies.remove(fontFamily);
      }
    }
  }

  Future<void> _migrateLegacyFont(
    LegacyCustomFontMigration migration,
  ) async {
    final legacyPath = _readNonEmptyString(migration.storageKeys.path);
    final legacyFamily = _readNonEmptyString(migration.storageKeys.family);
    if (migration.storageKeys.family == migration.selectionKey &&
        legacyFamily != null &&
        _isManagedFamily(legacyFamily)) {
      await _deleteRedundantLegacyMetadata(migration);
      return;
    }
    final sourceFile = legacyPath == null ? null : File(legacyPath);
    if (legacyFamily == null || sourceFile?.existsSync() != true) {
      await _resetInvalidLegacyFont(
        migration,
        unavailableFamily: legacyFamily,
      );
      return;
    }

    try {
      final legacyName = _readNonEmptyString(migration.storageKeys.name);
      final entry = await _importFont(
        CustomFontFileSource(
          sourcePath: sourceFile!.path,
          preferredDisplayName: legacyName,
        ),
      );
      final deleteKeys = migration.storageKeys.all.toSet()
        ..remove(migration.selectionKey);
      await _replaceSettings(
        values: {migration.selectionKey: entry.fontFamily},
        deleteKeys: deleteKeys,
      );

      final legacyDirectory = Directory(
        path.join(_supportDirectory(), migration.directoryName),
      );
      if (_isLegacyManagedFile(
        sourceFile,
        legacyDirectory,
        migration.fileNamePrefix,
      )) {
        await _deleteBestEffort(sourceFile);
      }
      await _cleanupLegacyManagedFiles(
        legacyDirectory,
        migration.fileNamePrefix,
      );
    } catch (_) {
      // Old keys and files remain recoverable. Re-import is content addressed.
    }
  }

  Future<void> _deleteRedundantLegacyMetadata(
    LegacyCustomFontMigration migration,
  ) async {
    try {
      final deletes = migration.storageKeys.all.toSet()
        ..remove(migration.selectionKey);
      if (deletes.isNotEmpty) {
        await _replaceSettings(deleteKeys: deletes);
      }
      await _cleanupLegacyManagedFiles(
        Directory(path.join(_supportDirectory(), migration.directoryName)),
        migration.fileNamePrefix,
      );
    } catch (_) {
      // The shared-pool selection remains usable; retry cleanup next startup.
    }
  }

  Future<void> _resetInvalidLegacyFont(
    LegacyCustomFontMigration migration, {
    String? unavailableFamily,
  }) async {
    try {
      final values = <String, Object?>{};
      final deletes = migration.storageKeys.all.toSet();
      final selected = _readNonEmptyString(migration.selectionKey);
      if (deletes.contains(migration.selectionKey) ||
          (unavailableFamily != null && selected == unavailableFamily)) {
        deletes.add(migration.selectionKey);
        for (final binding in config.selectionBindings) {
          if (binding.selectionKey != migration.selectionKey) continue;
          deletes.addAll(binding.fallbackDeletes);
          values.addAll(binding.fallbackValues);
          break;
        }
      }
      await _replaceSettings(values: values, deleteKeys: deletes);
      await _cleanupLegacyManagedFiles(
        Directory(path.join(_supportDirectory(), migration.directoryName)),
        migration.fileNamePrefix,
      );
    } catch (_) {
      // Leave recoverable state untouched if cleanup cannot be committed.
    }
  }

  Future<void> _pruneInvalidEntries() async {
    final unavailable = <String>{};
    final nextPaths = <String, String>{};
    for (final entry in _fontPaths.entries) {
      final file = File(entry.value);
      if (_isManagedEntry(entry.key, file, _fontDirectory) &&
          file.existsSync()) {
        nextPaths[entry.key] = entry.value;
      } else {
        unavailable.add(entry.key);
      }
    }
    final nextNames = <String, String>{
      for (final entry in _fontNames.entries)
        if (nextPaths.containsKey(entry.key)) entry.key: entry.value,
    };
    for (final binding in config.selectionBindings) {
      final selected = _readNonEmptyString(binding.selectionKey);
      if (selected != null &&
          _isManagedFamily(selected) &&
          !nextPaths.containsKey(selected)) {
        unavailable.add(selected);
      }
    }
    if (unavailable.isEmpty && nextNames.length == _fontNames.length) return;

    final values = <String, Object?>{
      config.libraryPathKey: nextPaths,
      config.libraryNameKey: nextNames,
    };
    final deletes = <String>{};
    _addSelectionFallbacks(unavailable, values, deletes);
    await _replaceSettings(values: values, deleteKeys: deletes);
    _fontPathsCache = nextPaths;
    _fontNamesCache = nextNames;
  }

  void _addSelectionFallbacks(
    Set<String> removed,
    Map<String, Object?> values,
    Set<String> deletes,
  ) {
    for (final binding in config.selectionBindings) {
      final selected = _readNonEmptyString(binding.selectionKey);
      if (selected == null || !removed.contains(selected)) continue;
      deletes
        ..add(binding.selectionKey)
        ..addAll(binding.fallbackDeletes);
      values.addAll(binding.fallbackValues);
    }
  }

  Future<void> _cleanupOrphanFiles() async {
    final referenced = _fontPaths.values.map(_normalizedPath).toSet();
    final fontDir = _fontDirectory;
    if (!fontDir.existsSync()) return;
    try {
      await for (final entity in fontDir.list()) {
        if (entity is! File) continue;
        final isOrphan =
            _isManagedFile(entity, fontDir) &&
            !referenced.contains(_normalizedPath(entity.path));
        if (isOrphan || _isTemporaryFile(entity, fontDir)) {
          await _deleteBestEffort(entity);
        }
      }
    } catch (_) {}
  }

  Future<void> _cleanupManagedFiles() async {
    final fontDir = _fontDirectory;
    if (!fontDir.existsSync()) return;
    try {
      await for (final entity in fontDir.list()) {
        if (entity is File &&
            (_isManagedFile(entity, fontDir) ||
                _isTemporaryFile(entity, fontDir))) {
          await _deleteBestEffort(entity);
        }
      }
    } catch (_) {}
  }

  Future<void> _cleanupLegacyManagedFiles(
    Directory directory,
    String prefix,
  ) async {
    if (!directory.existsSync()) return;
    try {
      await for (final entity in directory.list()) {
        if (entity is File && _isLegacyManagedFile(entity, directory, prefix)) {
          await _deleteBestEffort(entity);
        }
      }
    } catch (_) {}
  }

  bool _isManagedFile(File file, Directory fontDir) {
    if (!path.equals(
      _normalizedPath(path.dirname(file.path)),
      _normalizedPath(fontDir.path),
    )) {
      return false;
    }
    final extension = _extensionOf(file.path);
    if (extension == null) return false;
    final stem = path.basenameWithoutExtension(file.path);
    final prefix = '${config.fileNamePrefix}_';
    return stem.startsWith(prefix) &&
        _managedHash.hasMatch(stem.substring(prefix.length));
  }

  bool _isManagedEntry(
    String fontFamily,
    File file,
    Directory fontDir,
  ) {
    final familyHash = _managedFamilyHash(fontFamily);
    if (familyHash == null || !_isManagedFile(file, fontDir)) {
      return false;
    }
    final filePrefix = '${config.fileNamePrefix}_';
    final fileHash = path
        .basenameWithoutExtension(file.path)
        .substring(
          filePrefix.length,
        );
    return fileHash == familyHash;
  }

  bool _isManagedFamily(String fontFamily) =>
      _managedFamilyHash(fontFamily) != null;

  String? _managedFamilyHash(String fontFamily) {
    final familyPrefix = '${config.familyNamePrefix}_';
    if (!fontFamily.startsWith(familyPrefix)) return null;
    final hash = fontFamily.substring(familyPrefix.length);
    return _managedHash.hasMatch(hash) ? hash : null;
  }

  bool _isTemporaryFile(File file, Directory fontDir) {
    if (!path.equals(
      _normalizedPath(path.dirname(file.path)),
      _normalizedPath(fontDir.path),
    )) {
      return false;
    }
    return path
        .basename(file.path)
        .startsWith('.${config.fileNamePrefix}_importing_');
  }

  bool _isLegacyManagedFile(
    File file,
    Directory directory,
    String prefix,
  ) {
    if (!path.equals(
      _normalizedPath(path.dirname(file.path)),
      _normalizedPath(directory.path),
    )) {
      return false;
    }
    if (_extensionOf(file.path) == null) return false;
    final stem = path.basenameWithoutExtension(file.path);
    final fullPrefix = '${prefix}_';
    return stem.startsWith(fullPrefix) &&
        _legacyId.hasMatch(stem.substring(fullPrefix.length));
  }

  Future<void> _replaceSettings({
    Map<String, Object?> values = const {},
    Iterable<String> deleteKeys = const [],
  }) async {
    final deletes = deleteKeys.where((key) => !values.containsKey(key)).toSet();
    final keys = <String>{...values.keys, ...deletes};
    if (keys.isEmpty) return;
    final snapshot = _captureSettings(keys);
    try {
      if (deletes.isNotEmpty) {
        await settingsStore.deleteAll(deletes);
      }
      if (values.isNotEmpty) {
        await settingsStore.putAll(values);
      }
    } catch (operationError, operationStackTrace) {
      try {
        await _restoreSettings(snapshot, keys);
      } catch (rollbackError) {
        throw CustomFontSettingsException(
          operationError: operationError,
          rollbackError: rollbackError,
        );
      }
      Error.throwWithStackTrace(operationError, operationStackTrace);
    }
  }

  _CustomFontSettingsSnapshot _captureSettings(Iterable<String> keys) {
    final values = <String, Object?>{};
    for (final key in keys) {
      if (settingsStore.containsKey(key)) {
        values[key] = settingsStore.read(key);
      }
    }
    return _CustomFontSettingsSnapshot(values);
  }

  Future<void> _restoreSettings(
    _CustomFontSettingsSnapshot snapshot,
    Iterable<String> keys,
  ) async {
    await settingsStore.deleteAll(keys);
    if (snapshot.values.isNotEmpty) {
      await settingsStore.putAll(snapshot.values);
    }
  }

  Map<String, String> _readStringMap(String key) {
    final value = settingsStore.read(key);
    if (value is! Map) return {};
    return <String, String>{
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  String? _readNonEmptyString(String key) {
    final value = settingsStore.read(key);
    return value is String && value.isNotEmpty ? value : null;
  }

  String? _extensionOf(String fileName) {
    final extension = path
        .extension(fileName)
        .replaceFirst('.', '')
        .toLowerCase();
    return allowedExtensions.contains(extension) ? extension : null;
  }

  Future<String> _hashFile(File file) async =>
      (await sha1.bind(file.openRead()).first).toString();

  Future<String?> _tryHashFile(File file) async {
    try {
      return await _hashFile(file);
    } catch (_) {
      return null;
    }
  }

  String _normalizedPath(String value) => path.normalize(path.absolute(value));

  static Future<void> _loadFont({
    required String fontPath,
    required String fontFamily,
  }) async {
    final bytes = await File(fontPath).readAsBytes();
    await loadFontFromList(bytes, fontFamily: fontFamily);
  }

  static Future<void> _deleteBestEffort(File file) async {
    if (!file.existsSync()) return;
    try {
      await file.delete();
    } catch (_) {}
  }
}

final class _CustomFontSettingsSnapshot {
  _CustomFontSettingsSnapshot(Map<String, Object?> values)
    : values = Map.unmodifiable(values);

  final Map<String, Object?> values;
}
