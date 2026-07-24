import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/services/crash/crash_breadcrumbs.dart';
import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:PiliMax/utils/log_redactor.dart';
import 'package:crypto/crypto.dart';

class CrashReport {
  /// Hard limits keep corrupted/native input from turning the archive into an
  /// unbounded synchronous write or an oversized share payload.
  static const maxSerializedBytes = 256 * 1024;
  static const _maxReportIdLength = 128;
  static const _maxDateTextLength = 64;
  static const _maxExceptionTypeLength = 256;
  static const _maxRootCauseLength = 8192;
  static const _maxThreadLength = 256;
  static const _maxProcessLength = 256;
  static const _maxSystemInfoLength = 32 * 1024;
  static const _maxStackTraceLength = 128 * 1024;
  static const _maxEventCount = 40;
  static const _maxEventLength = 180;
  static const _maxSessionLength = 128;
  static const _maxContextLength = 512;

  final String reportId;
  final int crashedAtMillis;
  final String crashedAtText;
  final String exceptionType;
  final String rootCause;
  final String threadName;
  final String processName;
  final String systemInfo;
  final String stackTrace;
  final List<String> recentEvents;
  final CrashSource source;
  final CrashSeverity severity;
  final String sessionId;
  final String module;
  final String operation;
  final String route;
  final String reason;

  const CrashReport({
    required this.reportId,
    required this.crashedAtMillis,
    required this.crashedAtText,
    required this.exceptionType,
    required this.rootCause,
    required this.threadName,
    required this.processName,
    required this.systemInfo,
    required this.stackTrace,
    this.recentEvents = const [],
    this.source = CrashSource.unknown,
    this.severity = CrashSeverity.unknown,
    this.sessionId = 'legacy',
    this.module = 'unknown',
    this.operation = '',
    this.route = '',
    this.reason = '',
  });

  bool get isFatalCandidate => severity.isFatalCandidate;

  /// Applies the same bounds to reports created by factories, native input,
  /// JSON decoding, or callers constructing a report directly.
  CrashReport normalized() {
    if (_isAlreadyNormalized()) return this;
    final normalized = CrashReport(
      reportId: _context(reportId, 'unknown', maxLength: _maxReportIdLength),
      crashedAtMillis: crashedAtMillis,
      crashedAtText: _context(
        crashedAtText,
        _formatDateTime(_dateForMillis(crashedAtMillis)),
        maxLength: _maxDateTextLength,
      ),
      exceptionType: _context(
        exceptionType,
        'unknown',
        maxLength: _maxExceptionTypeLength,
      ),
      rootCause: _context(
        rootCause,
        'unknown',
        maxLength: _maxRootCauseLength,
      ),
      threadName: _context(
        threadName,
        'unknown',
        maxLength: _maxThreadLength,
      ),
      processName: _context(
        processName,
        'unknown',
        maxLength: _maxProcessLength,
      ),
      systemInfo: _context(
        systemInfo,
        '',
        maxLength: _maxSystemInfoLength,
      ),
      stackTrace: _context(
        stackTrace,
        '',
        maxLength: _maxStackTraceLength,
      ),
      recentEvents: _normalizeEvents(recentEvents),
      source: source,
      severity: severity,
      sessionId: _context(
        sessionId,
        'legacy',
        maxLength: _maxSessionLength,
      ),
      module: _context(module, 'unknown', maxLength: _maxContextLength),
      operation: _context(operation, '', maxLength: _maxContextLength),
      route: _context(route, '', maxLength: _maxContextLength),
      reason: _context(reason, '', maxLength: _maxContextLength),
    );
    return normalized._fitSerializedLimit();
  }

  bool _isAlreadyNormalized() {
    if (reportId.length > _maxReportIdLength ||
        crashedAtText.length > _maxDateTextLength ||
        exceptionType.length > _maxExceptionTypeLength ||
        rootCause.length > _maxRootCauseLength ||
        threadName.length > _maxThreadLength ||
        processName.length > _maxProcessLength ||
        systemInfo.length > _maxSystemInfoLength ||
        stackTrace.length > _maxStackTraceLength ||
        recentEvents.length > _maxEventCount ||
        sessionId.length > _maxSessionLength ||
        module.length > _maxContextLength ||
        operation.length > _maxContextLength ||
        route.length > _maxContextLength ||
        reason.length > _maxContextLength) {
      return false;
    }
    for (final event in recentEvents) {
      if (event.length > _maxEventLength ||
          _context(event, '', maxLength: _maxEventLength) != event) {
        return false;
      }
    }
    return _context(reportId, 'unknown', maxLength: _maxReportIdLength) ==
            reportId &&
        _context(crashedAtText, '', maxLength: _maxDateTextLength) ==
            crashedAtText &&
        _context(
              exceptionType,
              'unknown',
              maxLength: _maxExceptionTypeLength,
            ) ==
            exceptionType &&
        _context(rootCause, 'unknown', maxLength: _maxRootCauseLength) ==
            rootCause &&
        _context(threadName, 'unknown', maxLength: _maxThreadLength) ==
            threadName &&
        _context(processName, 'unknown', maxLength: _maxProcessLength) ==
            processName &&
        _context(systemInfo, '', maxLength: _maxSystemInfoLength) ==
            systemInfo &&
        _context(stackTrace, '', maxLength: _maxStackTraceLength) ==
            stackTrace &&
        _context(sessionId, 'legacy', maxLength: _maxSessionLength) ==
            sessionId &&
        _context(module, 'unknown', maxLength: _maxContextLength) == module &&
        _context(operation, '', maxLength: _maxContextLength) == operation &&
        _context(route, '', maxLength: _maxContextLength) == route &&
        _context(reason, '', maxLength: _maxContextLength) == reason &&
        _serializedByteLength(this) <= maxSerializedBytes;
  }

  CrashReport mergeWith(CrashReport other) {
    final attributionPreferred = _hasBetterAttribution(other, this)
        ? other
        : this;
    final attributionSecondary = identical(attributionPreferred, this)
        ? other
        : this;
    final severityPreferred =
        _severityRank(other.severity) > _severityRank(severity) ? other : this;
    String choose(String preferredValue, String fallback, {String empty = ''}) {
      return preferredValue != empty ? preferredValue : fallback;
    }

    return CrashReport(
      reportId: reportId,
      crashedAtMillis: crashedAtMillis <= other.crashedAtMillis
          ? crashedAtMillis
          : other.crashedAtMillis,
      crashedAtText: crashedAtMillis <= other.crashedAtMillis
          ? crashedAtText
          : other.crashedAtText,
      exceptionType: exceptionType,
      rootCause: rootCause,
      threadName: choose(
        attributionPreferred.threadName,
        attributionSecondary.threadName,
        empty: 'unknown',
      ),
      processName: choose(
        attributionPreferred.processName,
        attributionSecondary.processName,
        empty: 'unknown',
      ),
      systemInfo: other.systemInfo.length >= systemInfo.length
          ? other.systemInfo
          : systemInfo,
      stackTrace: other.stackTrace.length > stackTrace.length
          ? other.stackTrace
          : stackTrace,
      recentEvents: other.recentEvents.length > recentEvents.length
          ? other.recentEvents
          : recentEvents,
      source: attributionPreferred.source != CrashSource.unknown
          ? attributionPreferred.source
          : attributionSecondary.source,
      severity: severityPreferred.severity,
      sessionId: choose(
        attributionPreferred.sessionId,
        attributionSecondary.sessionId,
        empty: 'legacy',
      ),
      module: choose(
        attributionPreferred.module,
        attributionSecondary.module,
        empty: 'unknown',
      ),
      operation: choose(
        attributionPreferred.operation,
        attributionSecondary.operation,
      ),
      route: choose(attributionPreferred.route, attributionSecondary.route),
      reason: choose(
        attributionPreferred.reason,
        attributionSecondary.reason,
      ),
    ).normalized();
  }

  factory CrashReport.fromError(
    Object error,
    StackTrace? stackTrace, {
    String? systemInfo,
    CrashSource source = CrashSource.explicit,
    CrashSeverity severity = CrashSeverity.handled,
    String sessionId = 'legacy',
    String? module,
    String operation = '',
    String route = '',
    String reason = '',
  }) {
    final now = DateTime.now();
    final crashedAtMillis = now.millisecondsSinceEpoch;
    final exceptionType = _safeTypeName(error);
    final errorText = _safeToString(error, exceptionType);
    final rootCause = _context(
      errorText,
      exceptionType,
      maxLength: _maxRootCauseLength,
    );
    final stackTraceText = _context(
      stackTrace,
      '',
      maxLength: _maxStackTraceLength,
    );
    return CrashReport(
      reportId: _reportId(
        crashedAtMillis,
        exceptionType,
        rootCause,
        stackTraceText,
      ),
      crashedAtMillis: crashedAtMillis,
      crashedAtText: _formatDateTime(now),
      exceptionType: exceptionType,
      rootCause: rootCause,
      threadName: _context(Isolate.current.debugName, 'main'),
      processName: 'pid:$pid',
      systemInfo: _context(
        systemInfo ?? CrashReportSystemInfo.cached,
        '',
        maxLength: _maxSystemInfoLength,
      ),
      stackTrace: stackTraceText,
      recentEvents: CrashBreadcrumbs.snapshot(),
      source: source,
      severity: severity,
      sessionId: _context(sessionId, 'legacy'),
      module: _context(
        module ?? CrashModuleResolver.fromStack(stackTrace),
        'unknown',
      ),
      operation: _context(operation, ''),
      route: _context(route, ''),
      reason: _context(reason, ''),
    ).normalized();
  }

  factory CrashReport.fromNative(
    Map<String, dynamic> json, {
    required String systemInfo,
  }) {
    final crashedAtMillis = _millis(json['timestamp']);
    final exceptionType = _text(json['exceptionType'], 'NativeCrash');
    final rootCause = _context(
      json['message'],
      exceptionType,
      maxLength: _maxRootCauseLength,
    );
    final stackTrace = _context(
      json['stackTrace'],
      '',
      maxLength: _maxStackTraceLength,
    );
    final source = CrashSource.parse(json['source']);
    final pidValue = _number(json['pid']) ?? 0;
    final processName = _text(
      json['processName'],
      'pid:$pidValue',
    );
    final rawEvents = json['recentEvents'];
    final recentEvents = [
      for (final event in rawEvents is List<dynamic> ? rawEvents : const [])
        if (_safeToString(event, '').trim().isNotEmpty)
          _context(event, '', maxLength: 180),
    ];
    final capturedSystemInfo = _context(
      json['systemInfo'],
      '',
      maxLength: _maxSystemInfoLength,
    );
    final nativeInfo = _sanitize(
      <String>[
        systemInfo,
        if (capturedSystemInfo.isNotEmpty) capturedSystemInfo,
        'Captured app: ${_text(json['appVersion'], 'unknown')}',
        'Captured Android: ${_text(json['androidRelease'], 'unknown')} '
            '(SDK ${json['sdk'] ?? 'unknown'})',
        'Captured device: ${_text(json['manufacturer'], 'unknown')} '
            '${_text(json['model'], 'unknown')}',
        if (json['status'] != null) 'Exit status: ${json['status']}',
        if (json['importance'] != null)
          'Exit importance: ${json['importance']}',
        if (json['pss'] != null) 'Exit PSS: ${json['pss']}',
        if (json['rss'] != null) 'Exit RSS: ${json['rss']}',
      ].join('\n'),
    );
    DateTime crashedAt;
    try {
      crashedAt = DateTime.fromMillisecondsSinceEpoch(crashedAtMillis);
    } catch (_) {
      crashedAt = DateTime.now();
    }
    return CrashReport(
      reportId: () {
        final provided = _safeToString(json['reportId'], '').trim();
        if (provided.isNotEmpty) return provided;
        final recordId = _safeToString(json['recordId'], '').trim();
        if (recordId.isNotEmpty) return recordId;
        return _reportId(
          crashedAtMillis,
          exceptionType,
          rootCause,
          stackTrace,
        );
      }(),
      crashedAtMillis: crashedAtMillis,
      crashedAtText: _formatDateTime(crashedAt),
      exceptionType: exceptionType,
      rootCause: rootCause,
      threadName: _text(json['threadName'], 'unknown'),
      processName: processName,
      systemInfo: nativeInfo,
      stackTrace: stackTrace,
      recentEvents: recentEvents,
      source: source,
      severity: CrashSeverity.parse(json['severity']),
      sessionId: _context('native:$processName:$crashedAtMillis', 'native'),
      module: _context(json['module'], 'android'),
      reason: _context(json['reason'], 'native_failure'),
    ).normalized();
  }

  factory CrashReport.fromJson(Map<String, dynamic> json) {
    final crashedAtMillis = _millis(json['crashedAtMillis']);
    final reportId = _text(json['reportId'], '').trim();
    final rawEvents = json['recentEvents'];
    return CrashReport(
      reportId: reportId.isEmpty
          ? crashedAtMillis.toString().padLeft(12)
          : reportId,
      crashedAtMillis: crashedAtMillis,
      crashedAtText: _text(json['crashedAtText'], ''),
      exceptionType: _context(json['exceptionType'], 'unknown'),
      rootCause: _context(
        json['rootCause'],
        'unknown',
        maxLength: _maxRootCauseLength,
      ),
      threadName: _context(json['threadName'], 'unknown'),
      processName: _context(json['processName'], 'unknown'),
      systemInfo: _context(
        json['systemInfo'],
        '',
        maxLength: _maxSystemInfoLength,
      ),
      stackTrace: _context(
        json['stackTrace'],
        '',
        maxLength: _maxStackTraceLength,
      ),
      recentEvents: [
        for (final event in rawEvents is List<dynamic> ? rawEvents : const [])
          if (_safeToString(event, '').trim().isNotEmpty)
            _context(event, '', maxLength: 180),
      ],
      source: CrashSource.parse(json['source']),
      severity: CrashSeverity.parse(json['severity']),
      sessionId: _context(json['sessionId'], 'legacy'),
      module: _context(json['module'], 'unknown'),
      operation: _context(json['operation'], ''),
      route: _context(json['route'], ''),
      reason: _context(json['reason'], ''),
    ).normalized();
  }

  Map<String, dynamic> toJson() => normalized()._toJson();

  Map<String, dynamic> _toJson() => {
    'reportId': reportId,
    'crashedAtMillis': crashedAtMillis,
    'crashedAtText': crashedAtText,
    'exceptionType': exceptionType,
    'rootCause': rootCause,
    'threadName': threadName,
    'processName': processName,
    'systemInfo': systemInfo,
    'stackTrace': stackTrace,
    'recentEvents': recentEvents,
    'source': source.value,
    'severity': severity.value,
    'sessionId': sessionId,
    'module': module,
    'operation': operation,
    'route': route,
    'reason': reason,
  };

  String toClipboardText() {
    final report = normalized();
    final buffer = StringBuffer()
      ..writeln('Report ID: ${report.reportId}')
      ..writeln('Crash time: ${report.crashedAtText}')
      ..writeln('Exception type: ${report.exceptionType}')
      ..writeln('Root cause: ${report.rootCause}')
      ..writeln('Thread: ${report.threadName}')
      ..writeln('Process: ${report.processName}')
      ..writeln('Source: ${report.source.label} (${report.source.value})')
      ..writeln('Severity: ${report.severity.label} (${report.severity.value})')
      ..writeln('Module: ${report.module}')
      ..writeln(
        'Operation: ${report.operation.isEmpty ? 'unknown' : report.operation}',
      )
      ..writeln('Route: ${report.route.isEmpty ? 'unknown' : report.route}')
      ..writeln('Reason: ${report.reason.isEmpty ? 'unknown' : report.reason}')
      ..writeln('Session: ${report.sessionId}')
      ..writeln('System info:')
      ..writeln(report.systemInfo);
    if (report.recentEvents.isNotEmpty) {
      buffer.writeln('Recent app events:');
      for (final event in report.recentEvents) {
        buffer.writeln(event);
      }
    }
    buffer
      ..writeln('Stack trace:')
      ..writeln(report.stackTrace);
    return LogRedactor.redactText(buffer.toString());
  }

  CrashReport _fitSerializedLimit() {
    var report = this;
    if (_serializedByteLength(report) <= maxSerializedBytes) return report;

    report = _trimTextToFit(
      report,
      report.stackTrace,
      (value) => report._copyWith(stackTrace: value),
    );
    report = _trimTextToFit(
      report,
      report.systemInfo,
      (value) => report._copyWith(systemInfo: value),
    );
    report = _trimTextToFit(
      report,
      report.rootCause,
      (value) => report._copyWith(rootCause: value),
    );
    report = _trimEventsToFit(report);
    for (final field in <(String, CrashReport Function(String))>[
      (report.operation, (value) => report._copyWith(operation: value)),
      (report.route, (value) => report._copyWith(route: value)),
      (report.reason, (value) => report._copyWith(reason: value)),
      (report.module, (value) => report._copyWith(module: value)),
      (
        report.exceptionType,
        (value) => report._copyWith(exceptionType: value),
      ),
      (report.threadName, (value) => report._copyWith(threadName: value)),
      (report.processName, (value) => report._copyWith(processName: value)),
      (report.sessionId, (value) => report._copyWith(sessionId: value)),
      (report.reportId, (value) => report._copyWith(reportId: value)),
    ]) {
      report = _trimTextToFit(report, field.$1, field.$2);
      if (_serializedByteLength(report) <= maxSerializedBytes) return report;
    }
    return report;
  }

  static CrashReport _trimTextToFit(
    CrashReport report,
    String value,
    CrashReport Function(String value) update,
  ) {
    if (value.isEmpty || _serializedByteLength(report) <= maxSerializedBytes) {
      return report;
    }
    var low = 0;
    var high = value.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      final candidate = update(value.substring(0, middle));
      if (_serializedByteLength(candidate) <= maxSerializedBytes) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return update(value.substring(0, low));
  }

  static CrashReport _trimEventsToFit(CrashReport report) {
    if (_serializedByteLength(report) <= maxSerializedBytes) return report;
    final events = report.recentEvents;
    var low = 0;
    var high = events.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      final candidate = report._copyWith(
        recentEvents: events.take(middle).toList(growable: false),
      );
      if (_serializedByteLength(candidate) <= maxSerializedBytes) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return report._copyWith(
      recentEvents: events.take(low).toList(growable: false),
    );
  }

  CrashReport _copyWith({
    String? reportId,
    String? exceptionType,
    String? rootCause,
    String? threadName,
    String? processName,
    String? systemInfo,
    String? stackTrace,
    List<String>? recentEvents,
    String? sessionId,
    String? module,
    String? operation,
    String? route,
    String? reason,
  }) {
    return CrashReport(
      reportId: reportId ?? this.reportId,
      crashedAtMillis: crashedAtMillis,
      crashedAtText: crashedAtText,
      exceptionType: exceptionType ?? this.exceptionType,
      rootCause: rootCause ?? this.rootCause,
      threadName: threadName ?? this.threadName,
      processName: processName ?? this.processName,
      systemInfo: systemInfo ?? this.systemInfo,
      stackTrace: stackTrace ?? this.stackTrace,
      recentEvents: recentEvents ?? this.recentEvents,
      source: source,
      severity: severity,
      sessionId: sessionId ?? this.sessionId,
      module: module ?? this.module,
      operation: operation ?? this.operation,
      route: route ?? this.route,
      reason: reason ?? this.reason,
    );
  }

  static int _serializedByteLength(CrashReport report) {
    try {
      return utf8.encode(jsonEncode(report._toJson())).length;
    } catch (_) {
      return maxSerializedBytes + 1;
    }
  }

  static List<String> _normalizeEvents(Iterable<String> events) => [
    for (final event in events.take(_maxEventCount))
      if (_context(event, '', maxLength: _maxEventLength).isNotEmpty)
        _context(event, '', maxLength: _maxEventLength),
  ];

  static String _reportId(
    int crashedAtMillis,
    String exceptionType,
    String rootCause,
    String stackTrace,
  ) {
    final stackLines = const LineSplitter().convert(stackTrace);
    final firstStackLine = stackLines.isEmpty ? '' : stackLines.first;
    final seed = '$crashedAtMillis|$exceptionType|$rootCause|$firstStackLine';
    return sha256.convert(utf8.encode(seed)).toString().substring(0, 12);
  }

  static String _sanitize(String value) => LogRedactor.redactText(value);

  static String _safeTypeName(Object error) {
    try {
      return error.runtimeType.toString();
    } catch (_) {
      return 'UnknownError';
    }
  }

  static String _safeToString(Object? value, String fallback) {
    if (value == null) return fallback;
    try {
      return value.toString();
    } catch (_) {
      return fallback;
    }
  }

  static int _millis(Object? value) {
    try {
      final parsed = switch (value) {
        num() => value.toInt(),
        String() => int.tryParse(value),
        _ => null,
      };
      if (parsed != null) {
        DateTime.fromMillisecondsSinceEpoch(parsed);
        return parsed;
      }
    } catch (_) {}
    return DateTime.now().millisecondsSinceEpoch;
  }

  static int? _number(Object? value) {
    try {
      return switch (value) {
        num() => value.toInt(),
        String() => int.tryParse(value),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateForMillis(int value) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } catch (_) {
      return DateTime.now();
    }
  }

  static int _severityRank(CrashSeverity value) => switch (value) {
    CrashSeverity.fatal => 4,
    CrashSeverity.unhandled => 3,
    CrashSeverity.handled => 2,
    CrashSeverity.diagnostic => 1,
    CrashSeverity.unknown => 0,
  };

  static bool _hasBetterAttribution(
    CrashReport candidate,
    CrashReport current,
  ) {
    final candidateSource = _sourceRank(candidate.source);
    final currentSource = _sourceRank(current.source);
    if (candidateSource != currentSource) {
      return candidateSource > currentSource;
    }
    final candidateContext = _contextScore(candidate);
    final currentContext = _contextScore(current);
    return candidateContext > currentContext;
  }

  static int _sourceRank(CrashSource source) => switch (source) {
    CrashSource.explicit => 6,
    CrashSource.flutterFramework => 5,
    CrashSource.platformDispatcher => 5,
    CrashSource.androidUncaught => 4,
    CrashSource.androidExitInfo => 4,
    CrashSource.catcher => 2,
    CrashSource.unknown => 0,
  };

  static int _contextScore(CrashReport report) =>
      (report.module == 'unknown' ? 0 : 1) +
      (report.operation.isEmpty ? 0 : 1) +
      (report.route.isEmpty ? 0 : 1) +
      (report.reason.isEmpty ? 0 : 1);

  static String _text(Object? value, String fallback) {
    return _context(value, fallback, maxLength: 4096);
  }

  static String _context(
    Object? value,
    String fallback, {
    int maxLength = 512,
  }) {
    final raw = _safeToString(value, '').trim();
    final preboundedLength = maxLength * 4;
    final prebounded = raw.length <= preboundedLength
        ? raw
        : raw.substring(0, preboundedLength);
    final text = _sanitize(prebounded);
    final resolved = text.isEmpty ? fallback : text;
    return resolved.length <= maxLength
        ? resolved
        : resolved.substring(0, maxLength);
  }

  static String _formatDateTime(DateTime time) {
    return '${time.year.toString().padLeft(4, '0')}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}

abstract final class CrashReportSystemInfo {
  static String cached = _fallback();

  static void update(String value) {
    final bounded = CrashReport._context(
      value,
      '',
      maxLength: CrashReport._maxSystemInfoLength,
    );
    if (bounded.isNotEmpty) cached = bounded;
  }

  static String _fallback() {
    final usedMb = ProcessInfo.currentRss ~/ _bytesPerMebibyte;
    final maxMb = ProcessInfo.maxRss ~/ _bytesPerMebibyte;
    return [
      'App version: ${BuildConfig.versionName} (${BuildConfig.versionCode})',
      'Build time: ${BuildConfig.buildTime}',
      'Commit: ${BuildConfig.commitHash}',
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Locale: ${Platform.localeName}',
      'Memory: $usedMb MiB used / $maxMb MiB max',
    ].join('\n');
  }

  static const _bytesPerMebibyte = 1024 * 1024;
}
