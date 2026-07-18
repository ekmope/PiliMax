import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/utils/path_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

typedef CustomFontLoaderCallback =
    Future<void> Function({
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

final class CustomFontConfig {
  const CustomFontConfig({
    required this.directoryName,
    required this.fileNamePrefix,
    required this.familyNamePrefix,
    required this.storageKeys,
  }) : assert(directoryName != ''),
       assert(fileNamePrefix != ''),
       assert(familyNamePrefix != '');

  final String directoryName;
  final String fileNamePrefix;
  final String familyNamePrefix;
  final CustomFontStorageKeys storageKeys;
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

sealed class CustomFontSource {
  const CustomFontSource({required this.sourceName}) : assert(sourceName != '');

  final String sourceName;

  String get displayName => path.basename(sourceName);
}

final class CustomFontBytesSource extends CustomFontSource {
  const CustomFontBytesSource({
    required super.sourceName,
    required this.bytes,
  });

  final Uint8List bytes;
}

final class CustomFontFileSource extends CustomFontSource {
  const CustomFontFileSource({required this.sourcePath})
    : super(sourceName: sourcePath);

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

final class CustomFontManager {
  CustomFontManager({
    required this.config,
    required this._settingsStore,
    CustomFontLoaderCallback? fontLoader,
    String Function()? supportDirectory,
    int Function()? nowMilliseconds,
  }) : _fontLoader = fontLoader ?? _loadFont,
       _supportDirectory = supportDirectory ?? (() => appSupportDirPath),
       _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const List<String> allowedExtensions = ['ttf', 'otf'];
  static final RegExp _managedFileSuffix = RegExp(r'^\d+$');

  final CustomFontConfig config;
  final CustomFontSettingsStore _settingsStore;
  final CustomFontLoaderCallback _fontLoader;
  final String Function() _supportDirectory;
  final int Function() _nowMilliseconds;
  final Set<String> _loadedFamilies = {};
  final Lock _operationLock = Lock();

  String? get currentFontName => _readNonEmptyString(config.storageKeys.name);

  CustomFontSelection get currentSelection => CustomFontSelection(
    fontPath: _readNonEmptyString(config.storageKeys.path),
    fontFamily: _readNonEmptyString(config.storageKeys.family),
    displayName: currentFontName,
  );

  Directory get _fontDirectory => Directory(
    path.join(_supportDirectory(), config.directoryName),
  );

  Future<void> init() => _operationLock.synchronized(_init);

  Future<void> _init() async {
    final selection = currentSelection;
    if (!selection.isComplete) {
      await _clear();
      return;
    }

    final fontFile = File(selection.fontPath!);
    if (!fontFile.existsSync()) {
      await _clear();
      return;
    }

    try {
      await _fontLoader(
        fontPath: fontFile.path,
        fontFamily: selection.fontFamily!,
      );
      _loadedFamilies.add(selection.fontFamily!);
    } catch (_) {
      await _clear();
      return;
    }
    await _cleanupManagedFiles(excludePath: fontFile.path);
  }

  Future<bool> pickAndApply() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || result.files.isEmpty) {
      return false;
    }

    final picked = result.files.single;
    final selectedName = picked.path ?? picked.name;
    final CustomFontSource source;
    final sourcePath = picked.path;
    if (sourcePath != null &&
        sourcePath.isNotEmpty &&
        File(sourcePath).existsSync()) {
      source = CustomFontFileSource(sourcePath: sourcePath);
    } else {
      source = CustomFontBytesSource(
        sourceName: selectedName,
        bytes: await picked.readAsBytes(),
      );
    }

    await apply(source);
    return true;
  }

  Future<void> apply(CustomFontSource source) =>
      _operationLock.synchronized(() => _apply(source));

  Future<void> _apply(CustomFontSource source) async {
    final extension = path
        .extension(source.sourceName)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      throw UnsupportedError('unsupported font file: $extension');
    }

    final fontDir = _fontDirectory;
    if (!fontDir.existsSync()) {
      await fontDir.create(recursive: true);
    }

    final fontId = _nextAvailableFontId(fontDir);
    final fileName = '${config.fileNamePrefix}_$fontId.$extension';
    final fontFamily = '${config.familyNamePrefix}_$fontId';
    final targetFile = File(path.join(fontDir.path, fileName));

    try {
      await _copySource(source, targetFile);
      if (!targetFile.existsSync() || await targetFile.length() == 0) {
        throw StateError('font file is empty');
      }
      await _fontLoader(fontPath: targetFile.path, fontFamily: fontFamily);
      _loadedFamilies.add(fontFamily);
      await _replaceSettings({
        config.storageKeys.path: targetFile.path,
        config.storageKeys.family: fontFamily,
        config.storageKeys.name: source.displayName,
      });
      await _cleanupManagedFiles(excludePath: targetFile.path);
    } catch (error, stackTrace) {
      if (error is! CustomFontSettingsException &&
          !_isCurrentFontPath(targetFile.path)) {
        await _deleteBestEffort(targetFile);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> clear() => _operationLock.synchronized(_clear);

  Future<bool> _clear() async {
    final selection = currentSelection;
    final hadCustomFont =
        selection.fontPath != null ||
        selection.fontFamily != null ||
        selection.displayName != null;
    final snapshot = _captureSettings();
    if (snapshot.values.isNotEmpty) {
      await _replaceSettings(const {});
    }
    final deletedFiles = await _cleanupManagedFiles();
    return hadCustomFont || deletedFiles;
  }

  int _nextAvailableFontId(Directory fontDir) {
    var id = _nowMilliseconds();
    final currentFamily = currentSelection.fontFamily;
    while (_fontIdIsInUse(fontDir, id, currentFamily)) {
      id++;
    }
    return id;
  }

  bool _fontIdIsInUse(Directory fontDir, int id, String? currentFamily) {
    final family = '${config.familyNamePrefix}_$id';
    if (family == currentFamily || _loadedFamilies.contains(family)) {
      return true;
    }
    return allowedExtensions.any(
      (extension) => File(
        path.join(fontDir.path, '${config.fileNamePrefix}_$id.$extension'),
      ).existsSync(),
    );
  }

  Future<void> _copySource(CustomFontSource source, File targetFile) async {
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

  Future<void> _replaceSettings(Map<String, Object?> values) async {
    final snapshot = _captureSettings();
    try {
      if (values.isEmpty) {
        await _settingsStore.deleteAll(config.storageKeys.all);
      } else {
        await _settingsStore.putAll(values);
      }
    } catch (operationError, operationStackTrace) {
      try {
        await _restoreSettings(snapshot);
      } catch (rollbackError) {
        throw CustomFontSettingsException(
          operationError: operationError,
          rollbackError: rollbackError,
        );
      }
      Error.throwWithStackTrace(operationError, operationStackTrace);
    }
  }

  _CustomFontSettingsSnapshot _captureSettings() {
    final values = <String, Object?>{};
    for (final key in config.storageKeys.all) {
      if (_settingsStore.containsKey(key)) {
        values[key] = _settingsStore.read(key);
      }
    }
    return _CustomFontSettingsSnapshot(values);
  }

  Future<void> _restoreSettings(_CustomFontSettingsSnapshot snapshot) async {
    await _settingsStore.deleteAll(config.storageKeys.all);
    if (snapshot.values.isNotEmpty) {
      await _settingsStore.putAll(snapshot.values);
    }
  }

  bool _isCurrentFontPath(String candidatePath) {
    try {
      final currentPath = currentSelection.fontPath;
      return currentPath != null &&
          path.equals(
            _normalizedPath(currentPath),
            _normalizedPath(candidatePath),
          );
    } catch (_) {
      // If settings cannot be read after a failed update, retaining an
      // unreferenced managed file is safer than deleting a possibly active one.
      return true;
    }
  }

  Future<bool> _cleanupManagedFiles({String? excludePath}) async {
    final fontDir = _fontDirectory;
    if (!fontDir.existsSync()) {
      return false;
    }

    final normalizedExclude = excludePath == null
        ? null
        : _normalizedPath(excludePath);
    var deletedAny = false;
    try {
      await for (final entity in fontDir.list()) {
        if (entity is! File || !_isManagedFile(entity, fontDir)) {
          continue;
        }
        if (normalizedExclude != null &&
            path.equals(_normalizedPath(entity.path), normalizedExclude)) {
          continue;
        }
        try {
          await entity.delete();
          deletedAny = true;
        } catch (_) {}
      }
    } catch (_) {}
    return deletedAny;
  }

  bool _isManagedFile(File file, Directory fontDir) {
    if (!path.equals(
      _normalizedPath(path.dirname(file.path)),
      _normalizedPath(fontDir.path),
    )) {
      return false;
    }
    final extension = path
        .extension(file.path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      return false;
    }
    final stem = path.basenameWithoutExtension(file.path);
    final prefix = '${config.fileNamePrefix}_';
    return stem.startsWith(prefix) &&
        _managedFileSuffix.hasMatch(stem.substring(prefix.length));
  }

  String _normalizedPath(String value) => path.normalize(path.absolute(value));

  String? _readNonEmptyString(String key) {
    final value = _settingsStore.read(key);
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> _loadFont({
    required String fontPath,
    required String fontFamily,
  }) async {
    final bytes = await File(fontPath).readAsBytes();
    await (FontLoader(
      fontFamily,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  static Future<void> _deleteBestEffort(File file) async {
    if (!file.existsSync()) {
      return;
    }
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
