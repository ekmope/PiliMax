enum RouteRestoreAttemptOutcome {
  notStarted,
  checking,
  skipped,
  deferred,
  applied,
  failed,
}

/// A bounded description of this process's one startup restoration attempt.
///
/// This stays separate from historical crash reports and never stores route
/// arguments, external intents, or other user content.
class RouteRestoreDiagnostics {
  static final _code = RegExp(r'^[a-zA-Z0-9_]{1,96}$');
  static final _version = RegExp(r'^[a-zA-Z0-9.+_\-]{1,96}$');
  static final _commit = RegExp(r'^[a-fA-F0-9]{7,64}$');
  static const _maximumExportCharacters = 4096;
  static const _nativeDecisions = {
    'pending',
    'restore',
    'reject',
    'unknown',
    'unavailable',
  };
  static const _nativeBooleanKeys = [
    'priorBackground',
    'priorInvalidated',
    'taskMatches',
    'savedActivityState',
    'explicitNewLaunch',
    'packageUpdated',
    'lowMemoryKillReportSupported',
    'capturedFromHistory',
    'capturedLauncherCategory',
  ];
  static const _nativeIntegerKeys = [
    'exitReason',
    'exitStatus',
    'exitImportance',
  ];

  DateTime? _startedAt;
  final Stopwatch _elapsed = Stopwatch();
  RouteRestoreAttemptOutcome _outcome = RouteRestoreAttemptOutcome.notStarted;
  String _reason = 'not_started';
  Map<String, Object> _nativeAtAttempt = const {};

  bool get _finished =>
      _outcome != RouteRestoreAttemptOutcome.notStarted &&
      _outcome != RouteRestoreAttemptOutcome.checking;

  void start() {
    if (_startedAt != null || _finished) return;
    _startedAt = DateTime.now().toUtc();
    _outcome = RouteRestoreAttemptOutcome.checking;
    _reason = 'checking';
    _elapsed.start();
  }

  void recordNativeDecision(Map<Object?, Object?>? values) {
    // A timed-out method-channel future may still finish later. It must not
    // rewrite the native evidence used by an already completed Dart attempt.
    if (_outcome != RouteRestoreAttemptOutcome.checking) return;
    _nativeAtAttempt = _safeNativeValues(values);
  }

  void finish(RouteRestoreAttemptOutcome outcome, String reason) {
    if (_finished) return;
    _outcome = outcome;
    _reason = _safeCode(reason);
    if (_finished) _elapsed.stop();
  }

  String toExportText({
    required String versionName,
    required int versionCode,
    required String commitHash,
    required int processId,
    required bool enabled,
    Map<Object?, Object?>? nativeAtExport,
    String nativeReadStatus = 'available',
  }) {
    final buffer = StringBuffer()
      ..writeln('===== 本次启动恢复诊断 =====')
      ..writeln('以下仅描述导出时当前进程的启动恢复，与后续历史报告的发生时状态独立。')
      ..writeln(
        'Exported at (UTC): ${DateTime.now().toUtc().toIso8601String()}',
      )
      ..writeln(
        'App version: ${_safeMetadata(versionName, _version)} '
        '(${_safeNonnegativeInteger(versionCode)})',
      )
      ..writeln('Commit: ${_safeMetadata(commitHash, _commit)}')
      ..writeln('Process ID: ${_safeNonnegativeInteger(processId)}')
      ..writeln('Enabled at export: $enabled')
      ..writeln(
        'Attempt started (UTC): '
        '${_startedAt?.toIso8601String() ?? 'not_started'}',
      )
      ..writeln('Attempt elapsed (ms): ${_elapsed.elapsedMilliseconds}')
      ..writeln('Dart outcome: ${_outcome.name}')
      ..writeln('Dart reason: $_reason')
      ..writeln('nativeAtAttempt:');
    _writeNativeValues(buffer, _nativeAtAttempt);
    buffer
      ..writeln('Native read status at export: ${_safeCode(nativeReadStatus)}')
      ..writeln('nativeAtExport:');
    _writeNativeValues(buffer, _safeNativeValues(nativeAtExport));
    final text = buffer.toString();
    return text.length <= _maximumExportCharacters
        ? text
        : text.substring(0, _maximumExportCharacters);
  }

  static Map<String, Object> _safeNativeValues(Map<Object?, Object?>? values) {
    if (values == null) return const {};
    final safe = <String, Object>{};
    final decision = values['decision'];
    if (decision is String && _nativeDecisions.contains(decision)) {
      safe['decision'] = decision;
    }
    final reason = values['reason'];
    if (reason is String && _matchesEntireValue(reason, _code)) {
      safe['reason'] = reason;
    }
    for (final key in _nativeBooleanKeys) {
      final value = values[key];
      if (value is bool) safe[key] = value;
    }
    for (final key in _nativeIntegerKeys) {
      final value = values[key];
      if (value is int && value >= -2147483648 && value <= 2147483647) {
        safe[key] = value;
      }
    }
    return Map.unmodifiable(safe);
  }

  static void _writeNativeValues(
    StringBuffer buffer,
    Map<String, Object> values,
  ) {
    if (values.isEmpty) {
      buffer.writeln('  not_recorded');
      return;
    }
    for (final entry in values.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
  }

  static String _safeCode(String value) =>
      _matchesEntireValue(value, _code) ? value : 'unknown';

  static String _safeMetadata(String value, RegExp pattern) =>
      _matchesEntireValue(value, pattern) ? value : 'unknown';

  static bool _matchesEntireValue(String value, RegExp pattern) =>
      pattern.stringMatch(value) == value;

  static String _safeNonnegativeInteger(int value) =>
      value >= 0 && value <= 2147483647 ? '$value' : 'unknown';
}
