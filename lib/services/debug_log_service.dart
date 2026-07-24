import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/log_redactor.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DebugLogEntry {
  const DebugLogEntry({
    required this.tag,
    required this.message,
    required this.time,
    this.extra,
  });

  final String tag;
  final String message;
  final DateTime time;
  final Map<String, dynamic>? extra;

  factory DebugLogEntry.fromJson(Map<String, dynamic> json) => DebugLogEntry(
    tag: json['tag']?.toString() ?? 'unknown',
    message: json['message']?.toString() ?? '',
    time: DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
    extra: (json['extra'] as Map?)?.cast<String, dynamic>(),
  );

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'message': message,
    'time': time.toIso8601String(),
    if (extra != null && extra!.isNotEmpty) 'extra': extra,
  };

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('[${time.toIso8601String()}] ')
      ..write(tag)
      ..write(' ')
      ..write(message);
    if (extra != null && extra!.isNotEmpty) {
      buffer
        ..write('\n')
        ..write(const JsonEncoder.withIndent('  ').convert(extra));
    }
    return buffer.toString();
  }
}

abstract final class DebugLogService {
  static const _maxEntries = 1000;
  static File? _debugLogFile;
  static final List<DebugLogEntry> _memoryLogs = <DebugLogEntry>[];

  static bool get enabled =>
      GStorage.setting.get(SettingBoxKey.enableDebugLog, defaultValue: false);

  static Future<File> getDebugLogPath() async {
    if (_debugLogFile != null) return _debugLogFile!;
    final dir = (await getApplicationDocumentsDirectory()).path;
    final file = File(p.join(dir, '.pili_debug_logs.jsonl'));
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    return _debugLogFile = file;
  }

  static Future<void> log(
    String tag,
    String message, {
    Map<String, dynamic>? extra,
  }) async {
    final sanitizedExtra = LogRedactor.redact(extra);
    final entry = DebugLogEntry(
      tag: LogRedactor.redactText(tag),
      message: LogRedactor.redactText(message),
      time: DateTime.now(),
      extra: sanitizedExtra is Map
          ? sanitizedExtra.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : null,
    );

    if (kDebugMode) {
      debugPrint('[DebugLog][${entry.tag}] ${entry.message}');
      if (entry.extra case final extra? when extra.isNotEmpty) {
        debugPrint(const JsonEncoder.withIndent('  ').convert(extra));
      }
    }

    if (!enabled) return;

    try {
      _memoryLogs.add(entry);
      if (_memoryLogs.length > _maxEntries) {
        _memoryLogs.removeRange(0, _memoryLogs.length - _maxEntries);
      }
      final file = await getDebugLogPath();
      await file.writeAsString(
        _memoryLogs.map((entry) => jsonEncode(entry.toJson())).join('\n') +
            (_memoryLogs.isEmpty ? '' : '\n'),
        flush: true,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('DebugLogService.log failed: $error');
        debugPrint(stackTrace.toString());
      }
    }
  }

  static Future<List<DebugLogEntry>> readAll() async {
    try {
      final file = await getDebugLogPath();
      final lines = await file.readAsLines();
      final parsed = lines
          .where((line) => line.trim().isNotEmpty)
          .map((line) => DebugLogEntry.fromJson(jsonDecode(line)))
          .toList();
      _memoryLogs
        ..clear()
        ..addAll(parsed);
      return parsed.reversed.toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> exportText() async {
    final entries = await readAll();
    return LogRedactor.redactText(
      entries.map((entry) => entry.toString()).join('\n\n'),
    );
  }

  static Future<bool> clear() async {
    try {
      _memoryLogs.clear();
      final file = await getDebugLogPath();
      await file.writeAsBytes(const [], flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
