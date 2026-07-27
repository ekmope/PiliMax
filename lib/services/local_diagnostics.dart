import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/utils/log_redactor.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LocalDiagnosticArea { http, trial, player, audio }

final class LocalDiagnosticEntry {
  const LocalDiagnosticEntry({
    required this.area,
    required this.event,
    required this.timestamp,
    this.details = const {},
  });

  final LocalDiagnosticArea area;
  final String event;
  final DateTime timestamp;
  final Map<String, Object?> details;

  String encode({bool omitDetails = false, int? maxEventRunes}) {
    final eventRunes = event.runes;
    final boundedEvent =
        maxEventRunes != null && eventRunes.length > maxEventRunes
        ? '${String.fromCharCodes(eventRunes.take(maxEventRunes))}...'
        : event;
    final payload = <String, Object?>{
      'time': timestamp.toUtc().toIso8601String(),
      'area': area.name,
      'event': boundedEvent,
      if (omitDetails)
        'details': const {'truncated': true}
      else if (details.isNotEmpty)
        'details': details,
    };
    return jsonEncode(LogRedactor.redact(_jsonSafe(payload)));
  }

  static Object? _jsonSafe(Object? value) => switch (value) {
    null || bool() || num() || String() => value,
    DateTime() => value.toUtc().toIso8601String(),
    Duration() => value.inMilliseconds,
    Enum() => value.name,
    Map() => {
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafe(entry.value),
    },
    Iterable() => [for (final item in value) _jsonSafe(item)],
    _ => value.toString(),
  };
}

final class LocalDiagnosticLogStore {
  LocalDiagnosticLogStore({
    required this.directory,
    this.maxFileBytes = 512 * 1024,
    this.maxEntryBytes = 32 * 1024,
  }) : assert(maxFileBytes >= 256),
       assert(maxEntryBytes > 0);

  final Directory directory;
  final int maxFileBytes;
  final int maxEntryBytes;

  File get currentFile => File(
    p.join(directory.path, '.pilimax_local_diagnostics.log'),
  );

  File get rotatedFile => File(
    p.join(directory.path, '.pilimax_local_diagnostics.1.log'),
  );

  Future<void> _tail = Future.value();

  Future<void> append(LocalDiagnosticEntry entry) => _schedule(() async {
    await directory.create(recursive: true);
    final encoded = _boundedEncoding(entry);
    final bytes = utf8.encode('$encoded\n');
    final current = currentFile;
    if (_exists(current) &&
        await current.length() + bytes.length > maxFileBytes) {
      await _rotate();
    }
    await current.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  });

  Future<String> readText() => _schedule(() async {
    final buffer = StringBuffer();
    for (final file in [rotatedFile, currentFile]) {
      if (!_exists(file)) continue;
      final text = await file.readAsString();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
        buffer.writeln();
      }
      buffer.write(text);
    }
    return LogRedactor.redactText(buffer.toString());
  });

  Future<void> clear() => _schedule(() async {
    for (final file in [currentFile, rotatedFile]) {
      if (_exists(file)) await file.delete();
    }
  });

  String _boundedEncoding(LocalDiagnosticEntry entry) {
    final limit = math.min(maxEntryBytes, maxFileBytes - 1);
    var encoded = entry.encode();
    if (utf8.encode(encoded).length <= limit) return encoded;

    encoded = entry.encode(
      omitDetails: true,
      maxEventRunes: math.max(16, limit ~/ 4),
    );
    if (utf8.encode(encoded).length <= limit) return encoded;

    return jsonEncode({
      'time': entry.timestamp.toUtc().toIso8601String(),
      'area': entry.area.name,
      'event': '[truncated]',
    });
  }

  Future<void> _rotate() async {
    final current = currentFile;
    if (!_exists(current)) return;
    final rotated = rotatedFile;
    if (_exists(rotated)) await rotated.delete();
    await current.rename(rotated.path);
  }

  static bool _exists(File file) =>
      FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<T> _schedule<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

abstract final class LocalDiagnostics {
  static Future<LocalDiagnosticLogStore>? _store;

  static Future<void> record(
    LocalDiagnosticArea area,
    String event, {
    Map<String, Object?> details = const {},
  }) async {
    if (!BuildConfig.localDiagnostics) return;
    try {
      final store = await (_store ??= _createStore());
      await store.append(
        LocalDiagnosticEntry(
          area: area,
          event: event,
          timestamp: DateTime.now(),
          details: details,
        ),
      );
    } catch (error) {
      debugPrint('LocalDiagnostics.record failed: ${error.runtimeType}');
    }
  }

  static Future<String> readText() async {
    if (!BuildConfig.localDiagnostics) return '';
    try {
      return await (await (_store ??= _createStore())).readText();
    } catch (error) {
      debugPrint('LocalDiagnostics.readText failed: ${error.runtimeType}');
      return '';
    }
  }

  static Future<bool> clear() async {
    if (!BuildConfig.localDiagnostics) return false;
    try {
      await (await (_store ??= _createStore())).clear();
      return true;
    } catch (error) {
      debugPrint('LocalDiagnostics.clear failed: ${error.runtimeType}');
      return false;
    }
  }

  static Future<LocalDiagnosticLogStore> _createStore() async =>
      LocalDiagnosticLogStore(
        directory: await getApplicationDocumentsDirectory(),
      );
}
