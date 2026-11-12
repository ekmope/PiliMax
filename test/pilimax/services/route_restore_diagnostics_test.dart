import 'package:PiliMax/pilimax/services/route_restore_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

String _export(
  RouteRestoreDiagnostics diagnostics, {
  bool enabled = true,
  Map<Object?, Object?>? nativeAtExport,
  String nativeReadStatus = 'available',
}) => diagnostics.toExportText(
  versionName: '2.2.0-7f002bea9',
  versionCode: 6118,
  commitHash: '7f002bea9d89a522bc3cfe33abfc461fdae2d3c7',
  processId: 1234,
  enabled: enabled,
  nativeAtExport: nativeAtExport,
  nativeReadStatus: nativeReadStatus,
);

String _attemptSection(String text) => text
    .split('nativeAtAttempt:\n')
    .last
    .split('Native read status at export:')
    .first;

void main() {
  test(
    'freezes attempt evidence and outcome after the first final decision',
    () {
      final diagnostics = RouteRestoreDiagnostics()
        ..start()
        ..recordNativeDecision({
          'decision': 'pending',
          'reason': 'awaiting_exit_history',
        })
        ..finish(RouteRestoreAttemptOutcome.deferred, 'native_timeout');
      final beforeLateReply = _attemptSection(_export(diagnostics));

      diagnostics
        ..recordNativeDecision({'decision': 'restore', 'reason': 'late_result'})
        ..finish(RouteRestoreAttemptOutcome.applied, 'navigation_requested')
        ..start();
      final text = _export(
        diagnostics,
        nativeAtExport: {'decision': 'restore', 'reason': 'late_result'},
      );

      expect(_attemptSection(text), beforeLateReply);
      expect(text, contains('Dart outcome: deferred\n'));
      expect(text, contains('Dart reason: native_timeout\n'));
      expect(text, contains('nativeAtExport:\n  decision: restore\n'));
    },
  );

  test('keeps native permission separate from a Dart navigation veto', () {
    final diagnostics = RouteRestoreDiagnostics()
      ..start()
      ..recordNativeDecision({
        'decision': 'restore',
        'reason': 'system_reclaim_3',
        'priorBackground': true,
        'capturedFromHistory': false,
        'capturedLauncherCategory': true,
      })
      ..finish(RouteRestoreAttemptOutcome.skipped, 'user_navigation');
    final text = _export(diagnostics);

    expect(text, contains('Dart outcome: skipped\n'));
    expect(text, contains('Dart reason: user_navigation\n'));
    expect(_attemptSection(text), contains('decision: restore\n'));
    expect(_attemptSection(text), contains('capturedFromHistory: false\n'));
    expect(_attemptSection(text), contains('capturedLauncherCategory: true\n'));
    expect(text, isNot(contains('rendered_success')));
  });

  test('can export diagnostics without any stored state or crash report', () {
    for (final reason in ['no_stored_state', 'disabled']) {
      final diagnostics = RouteRestoreDiagnostics()
        ..start()
        ..finish(RouteRestoreAttemptOutcome.skipped, reason);
      final text = _export(diagnostics, enabled: reason != 'disabled');

      expect(text, startsWith('===== 本次启动恢复诊断 =====\n'));
      expect(text, contains('与后续历史报告的发生时状态独立'));
      expect(text, contains('Dart reason: $reason\n'));
      expect(text, contains('nativeAtAttempt:\n  not_recorded\n'));
      expect(text, contains('Enabled at export: ${reason != 'disabled'}\n'));
      expect(text, contains('App version: 2.2.0-7f002bea9 (6118)\n'));
      expect(text, contains('Process ID: 1234\n'));
      expect(text, contains('Attempt started (UTC): '));
      expect(text, contains('Exported at (UTC): '));
    }
  });

  test('filters unknown fields and wrong primitive types from native maps', () {
    final source = <Object?, Object?>{
      'decision': 'restore',
      'reason': 'system_reclaim_3',
      'priorBackground': 'true',
      'taskMatches': true,
      'exitReason': 3,
      'exitStatus': 1.5,
      'exitImportance': 2147483648,
      'arguments': {'keyword': 'private_search', 'cid': 123},
      'intentData': 'https://private.example/?token=secret',
      'capturedFromHistory': [true],
    };
    final diagnostics = RouteRestoreDiagnostics()
      ..start()
      ..recordNativeDecision(source)
      ..finish(RouteRestoreAttemptOutcome.applied, 'navigation_requested');
    source['reason'] = 'mutated_after_capture';
    final text = _export(diagnostics, nativeAtExport: source);

    expect(_attemptSection(text), contains('reason: system_reclaim_3\n'));
    expect(text, contains('taskMatches: true\n'));
    expect(text, contains('exitReason: 3\n'));
    for (final rejected in [
      'priorBackground:',
      'exitStatus:',
      'exitImportance:',
      'arguments',
      'keyword',
      'private_search',
      'intentData',
      'private.example',
      'secret',
      'capturedFromHistory:',
    ]) {
      expect(text, isNot(contains(rejected)));
    }
  });

  test('rejects injected codes and metadata while bounding export length', () {
    final longValue = 'x' * 100000;
    final diagnostics = RouteRestoreDiagnostics()
      ..start()
      ..recordNativeDecision({
        'decision': 'restore\npassword=secret',
        'reason': longValue,
        'taskMatches': true,
      })
      ..finish(RouteRestoreAttemptOutcome.failed, 'error\npassword=secret');
    final text = diagnostics.toExportText(
      versionName: 'version\npassword=secret',
      versionCode: -1,
      commitHash: longValue,
      processId: -1,
      enabled: true,
      nativeAtExport: {'reason': 'https://private.example/path'},
      nativeReadStatus: longValue,
    );

    expect(text.length, lessThanOrEqualTo(4096));
    expect(text, contains('Dart reason: unknown\n'));
    expect(text, contains('App version: unknown (unknown)\n'));
    expect(text, contains('Commit: unknown\n'));
    expect(text, contains('Process ID: unknown\n'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('private.example')));
    expect(text, isNot(contains(longValue)));
  });

  test('does not accept a line terminator after an otherwise valid code', () {
    final diagnostics = RouteRestoreDiagnostics()
      ..start()
      ..recordNativeDecision({'reason': 'valid_reason\n'})
      ..finish(RouteRestoreAttemptOutcome.failed, 'valid_reason\n');
    final text = _export(diagnostics, nativeReadStatus: 'timeout\n');

    expect(text, contains('Dart reason: unknown\n'));
    expect(text, contains('Native read status at export: unknown\n'));
    expect(text, isNot(contains('valid_reason')));
  });

  test('read failures can be exported without changing the frozen attempt', () {
    final diagnostics = RouteRestoreDiagnostics()
      ..start()
      ..recordNativeDecision({
        'decision': 'unknown',
        'reason': 'no_exit_record',
      })
      ..finish(RouteRestoreAttemptOutcome.deferred, 'native_unknown');
    final beforeExport = _attemptSection(_export(diagnostics));
    for (final status in ['timeout', 'unavailable', 'not_android']) {
      final text = _export(diagnostics, nativeReadStatus: status);

      expect(text, contains('Native read status at export: $status\n'));
      expect(_attemptSection(text), beforeExport);
      expect(text, contains('Dart reason: native_unknown\n'));
      expect(text, contains('nativeAtExport:\n  not_recorded\n'));
    }
  });

  test('exports a not-started attempt and start is idempotent', () {
    final diagnostics = RouteRestoreDiagnostics()
      ..recordNativeDecision({'decision': 'restore', 'reason': 'too_early'});
    expect(_export(diagnostics), contains('Dart outcome: notStarted\n'));
    expect(
      _export(diagnostics),
      contains('Attempt started (UTC): not_started\n'),
    );

    diagnostics.start();
    final startLine = _export(diagnostics)
        .split('\n')
        .singleWhere((line) => line.startsWith('Attempt started (UTC):'));
    diagnostics.start();
    expect(_export(diagnostics), contains('$startLine\n'));
    expect(_export(diagnostics), contains('Dart outcome: checking\n'));
  });
}
