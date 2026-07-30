import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:PiliMax/services/crash/crash_report.dart';
import 'package:PiliMax/services/crash/crash_report_archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class CrashReportStore {
  static const _directoryName = 'crash_reports';
  static const _fileName = 'crash_report.json';
  static List<File>? _files;
  static Future<void> _archiveMutationTail = Future<void>.value();

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
  }) => saveBatch([(report: report, makePending: makePending)]);

  /// Persists multiple reports with one archive read and one atomic write.
  ///
  /// Entries are applied in order so batching preserves the same duplicate and
  /// pending-report behavior as calling [saveSync] for each entry.
  static void saveBatchSync(
    Iterable<({CrashReport report, bool makePending})> entries,
  ) {
    final iterator = entries.iterator;
    if (!iterator.moveNext()) return;

    var archive = _loadArchive();
    do {
      final entry = iterator.current;
      archive = archive.add(entry.report, makePending: entry.makePending);
    } while (iterator.moveNext());
    _saveArchiveSync(archive);
  }

  static Future<void> saveBatch(
    Iterable<({CrashReport report, bool makePending})> entries,
  ) {
    final batch = [
      for (final entry in entries)
        <String, Object?>{
          'report': entry.report.toJson(),
          'makePending': entry.makePending,
        },
    ];
    if (batch.isEmpty) return Future.value();
    final paths = [for (final file in _requireFiles()) file.path];
    return _serializeArchiveMutation(
      () => Isolate.run(() => _saveBatchInBackground(paths, batch)),
    );
  }

  /// Imports native reports outside the UI isolate. Returned record IDs must
  /// be acknowledged only after the archive write completes.
  static Future<List<String>> importNativeBatch(
    List<Map<String, dynamic>> reports, {
    required String systemInfo,
  }) {
    if (reports.isEmpty) return Future.value(const []);
    final paths = [for (final file in _requireFiles()) file.path];
    final batch = [
      for (final report in reports) Map<String, Object?>.from(report),
    ];
    return _serializeArchiveMutation(
      () => Isolate.run(
        () => _importNativeBatchInBackground(paths, batch, systemInfo),
      ),
    );
  }

  static CrashReport? load() => _loadArchive().pendingReport;

  static List<CrashReport> loadAll() => _loadArchive().reports;

  static Future<void> markSeen(String reportId) {
    final paths = [for (final file in _requireFiles()) file.path];
    return _serializeArchiveMutation(
      () => Isolate.run(() => _markSeenInBackground(paths, reportId)),
    );
  }

  static Future<void> remove(String reportId) {
    final paths = [for (final file in _requireFiles()) file.path];
    return _serializeArchiveMutation(
      () => Isolate.run(() => _removeInBackground(paths, reportId)),
    );
  }

  static void _saveArchiveSync(CrashReportArchive archive) {
    _saveArchiveToFiles(_requireFiles(), archive);
  }

  static void _saveArchiveToFiles(
    List<File> files,
    CrashReportArchive archive,
  ) {
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
    return _loadArchiveFromFiles(_requireFiles());
  }

  static CrashReportArchive _loadArchiveFromFiles(List<File> files) {
    final replicas = <({int modifiedAt, CrashReportArchive archive})>[];
    for (final file in files) {
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

  static Future<void> clear() {
    final paths = [for (final file in _requireFiles()) file.path];
    return _serializeArchiveMutation(
      () => Isolate.run(() => _clearInBackground(paths)),
    );
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

  static Future<T> _serializeArchiveMutation<T>(
    Future<T> Function() operation,
  ) {
    final result = _archiveMutationTail.then((_) => operation());
    _archiveMutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static void _saveBatchInBackground(
    List<String> paths,
    List<Map<String, Object?>> entries,
  ) {
    final files = [for (final path in paths) File(path)];
    var archive = _loadArchiveFromFiles(files);
    for (final entry in entries) {
      final rawReport = entry['report'];
      if (rawReport is! Map) continue;
      final report = CrashReport.fromJson(
        rawReport.map((key, value) => MapEntry(key.toString(), value)),
      );
      archive = archive.add(
        report,
        makePending: entry['makePending'] == true,
      );
    }
    _saveArchiveToFiles(files, archive);
  }

  static List<String> _importNativeBatchInBackground(
    List<String> paths,
    List<Map<String, Object?>> entries,
    String systemInfo,
  ) {
    final files = [for (final path in paths) File(path)];
    var archive = _loadArchiveFromFiles(files);
    final acknowledged = <String>[];
    var changed = false;
    for (final entry in entries) {
      final recordId = entry['recordId']?.toString();
      try {
        final report = CrashReport.fromNative(
          Map<String, dynamic>.from(entry),
          systemInfo: systemInfo,
        );
        if (!_isDuplicateGenericExit(archive, report)) {
          archive = archive.add(
            report,
            makePending: report.isFatalCandidate,
          );
          changed = true;
        }
        if (recordId != null && recordId.isNotEmpty) {
          acknowledged.add(recordId);
        }
      } catch (_) {
        // Keep a malformed report staged for a later diagnostic attempt.
      }
    }
    if (changed) {
      _saveArchiveToFiles(files, archive);
    }
    return acknowledged;
  }

  static void _markSeenInBackground(List<String> paths, String reportId) {
    final files = [for (final path in paths) File(path)];
    _saveArchiveToFiles(
      files,
      _loadArchiveFromFiles(files).markSeen(reportId),
    );
  }

  static void _removeInBackground(List<String> paths, String reportId) {
    final files = [for (final path in paths) File(path)];
    _saveArchiveToFiles(
      files,
      _loadArchiveFromFiles(files).remove(reportId),
    );
  }

  static void _clearInBackground(List<String> paths) {
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
  }

  static bool _isDuplicateGenericExit(
    CrashReportArchive archive,
    CrashReport report,
  ) {
    if (report.source != CrashSource.androidExitInfo ||
        (report.reason != 'java_crash' && report.reason != 'native_crash')) {
      return false;
    }
    final pending = archive.pendingReport;
    if (pending == null || !pending.isFatalCandidate) return false;
    return (pending.crashedAtMillis - report.crashedAtMillis).abs() <= 10_000;
  }
}
