import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliMax/services/crash/crash_report.dart';
import 'package:PiliMax/services/crash/crash_report_archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class CrashReportStore {
  static const _directoryName = 'crash_reports';
  static const _fileName = 'crash_report.json';
  static List<File>? _files;

  static bool get isInitialized => _files != null;

  static Future<void> ensureInitialized() async {
    if (_files != null) return;
    // Keep crash data in an application-owned location. Documents and the
    // system temporary directory are user-visible/shared on desktop platforms
    // and are not safe places for a predictable report filename.
    final supportDirectory = await _tryDirectory(
      getApplicationSupportDirectory,
    );
    final cacheDirectory = supportDirectory == null
        ? await _tryDirectory(getApplicationCacheDirectory)
        : null;
    final directory = supportDirectory ?? cacheDirectory;
    if (directory == null) {
      throw const FileSystemException(
        'No directory is available for crash reports.',
      );
    }
    final path = p.join(
      p.normalize(p.absolute(directory.path)),
      _directoryName,
      _fileName,
    );
    _files = [File(path)];
  }

  static Future<Directory?> _tryDirectory(
    Future<Directory> Function() getter,
  ) async {
    try {
      return await getter();
    } catch (_) {
      return null;
    }
  }

  static void saveSync(CrashReport report, {required bool makePending}) {
    _saveArchiveSync(_loadArchive().add(report, makePending: makePending));
  }

  static Future<void> save(
    CrashReport report, {
    required bool makePending,
  }) => Future.sync(() => saveSync(report, makePending: makePending));

  static CrashReport? load() => _loadArchive().pendingReport;

  static List<CrashReport> loadAll() => _loadArchive().reports;

  static Future<void> markSeen(String reportId) =>
      Future.sync(() => _saveArchiveSync(_loadArchive().markSeen(reportId)));

  static Future<void> remove(String reportId) =>
      Future.sync(() => _saveArchiveSync(_loadArchive().remove(reportId)));

  static void _saveArchiveSync(CrashReportArchive archive) {
    final files = _requireFiles();
    final payload = jsonEncode(archive.toJson());
    if (utf8.encode(payload).length > CrashReportArchive.maxSerializedBytes) {
      throw const FileSystemException(
        'Crash report archive exceeds its size limit.',
      );
    }
    var saved = false;
    for (final file in files) {
      try {
        _writeAtomically(file, payload);
        saved = true;
      } catch (_) {
        continue;
      }
    }
    if (!saved) {
      throw FileSystemException(
        'Unable to persist crash report.',
        files.first.path,
      );
    }
  }

  static CrashReportArchive _loadArchive() {
    final replicas = <({int modifiedAt, CrashReportArchive archive})>[];
    for (final file in _requireFiles()) {
      if (!file.existsSync()) continue;
      try {
        if (file.lengthSync() > CrashReportArchive.maxSerializedBytes) {
          continue;
        }
        replicas.add(
          (
            modifiedAt: file.lastModifiedSync().millisecondsSinceEpoch,
            archive: CrashReportArchive.fromJson(
              jsonDecode(file.readAsStringSync()),
            ),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    if (replicas.isEmpty) return const CrashReportArchive.empty();
    var latestModifiedAt = replicas.first.modifiedAt;
    for (final replica in replicas.skip(1)) {
      if (replica.modifiedAt > latestModifiedAt) {
        latestModifiedAt = replica.modifiedAt;
      }
    }
    return CrashReportArchive.mergeReplicas(
      replicas
          .where((replica) => replica.modifiedAt == latestModifiedAt)
          .map((replica) => replica.archive),
    );
  }

  static Future<void> clear() async {
    for (final file in _requireFiles()) {
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }

  static List<File> _requireFiles() {
    final files = _files;
    if (files == null) {
      throw StateError('CrashReportStore.ensureInitialized() was not called.');
    }
    return files;
  }

  static void _writeAtomically(File file, String payload) {
    file.parent.createSync(recursive: true);
    final tempFile = _createExclusiveTempFile(file);
    try {
      tempFile.writeAsStringSync(payload, flush: true);
      try {
        tempFile.renameSync(file.path);
      } on FileSystemException {
        // Windows does not replace an existing destination on rename. The
        // fallback is still confined to the private directory and uses the
        // already flushed random temporary file.
        tempFile
          ..copySync(file.path)
          ..deleteSync();
      }
    } catch (_) {
      try {
        if (tempFile.existsSync()) tempFile.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  static File _createExclusiveTempFile(File file) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final tempFile = File('${file.path}.${_randomSuffix()}.tmp');
      try {
        tempFile.createSync(exclusive: true);
        return tempFile;
      } on FileSystemException {
        continue;
      }
    }
    throw FileSystemException(
      'Unable to create a private temporary crash report file.',
      file.path,
    );
  }

  static String _randomSuffix() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
