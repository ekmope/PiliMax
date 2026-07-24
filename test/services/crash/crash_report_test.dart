import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:PiliMax/services/crash/crash_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashReport', () {
    test('preserves attribution fields through JSON', () {
      const report = CrashReport(
        reportId: 'report',
        crashedAtMillis: 1,
        crashedAtText: 'time',
        exceptionType: 'StateError',
        rootCause: 'failure',
        threadName: 'main',
        processName: 'pid:1',
        systemInfo: 'system',
        stackTrace: 'stack',
        source: CrashSource.platformDispatcher,
        severity: CrashSeverity.fatal,
        sessionId: 'session',
        module: 'pages/web_qr_auth',
        operation: 'scanCamera',
        route: '/webQrAuth',
        reason: 'uncaught',
      );

      final decoded = CrashReport.fromJson(report.toJson());

      expect(decoded.source, CrashSource.platformDispatcher);
      expect(decoded.severity, CrashSeverity.fatal);
      expect(decoded.sessionId, 'session');
      expect(decoded.module, 'pages/web_qr_auth');
      expect(decoded.operation, 'scanCamera');
      expect(decoded.route, '/webQrAuth');
      expect(decoded.reason, 'uncaught');
      expect(decoded.isFatalCandidate, isTrue);
    });

    test('migrates legacy reports as non-fatal unknown attribution', () {
      final report = CrashReport.fromJson({
        'reportId': 'legacy',
        'crashedAtMillis': 1,
        'crashedAtText': 'time',
        'exceptionType': 'String',
        'rootCause': 'diagnostic',
        'systemInfo': 'system',
        'stackTrace': '',
      });

      expect(report.source, CrashSource.unknown);
      expect(report.severity, CrashSeverity.unknown);
      expect(report.sessionId, 'legacy');
      expect(report.isFatalCandidate, isFalse);
    });

    test('classifies platform callbacks from delegated handler results', () {
      expect(
        CrashSeverity.fromPlatformHandled(true),
        CrashSeverity.unhandled,
      );
      expect(
        CrashSeverity.fromPlatformHandled(false),
        CrashSeverity.fatal,
      );
    });

    test('resolves the application module from a Flutter stack', () {
      final stackTrace = StackTrace.fromString(
        '#0 WebQrAuthController.scan '
        '(package:PiliMax/pages/web_qr_auth/controller.dart:42)',
      );

      expect(
        CrashModuleResolver.fromStack(stackTrace),
        'pages/web_qr_auth',
      );
    });

    test('imports Android native crash attribution', () {
      final report = CrashReport.fromNative({
        'timestamp': 1000,
        'source': 'android_uncaught',
        'severity': 'fatal',
        'module': 'qr',
        'reason': 'uncaught_exception',
        'exceptionType': 'java.lang.IllegalStateException',
        'message': 'camera failed',
        'threadName': 'main',
        'processName': 'com.PiliMax.android',
        'stackTrace': 'native stack',
      }, systemInfo: 'current system');

      expect(report.source, CrashSource.androidUncaught);
      expect(report.severity, CrashSeverity.fatal);
      expect(report.module, 'qr');
      expect(report.reason, 'uncaught_exception');
      expect(report.stackTrace, 'native stack');
      expect(report.isFatalCandidate, isTrue);
    });

    test('imports Android process-exit metadata and recent events', () {
      final report = CrashReport.fromNative({
        'timestamp': 2000,
        'source': 'android_exit_info',
        'severity': 'fatal',
        'module': 'android_process',
        'reason': 'anr',
        'exceptionType': 'ApplicationExitInfo',
        'message': 'Input dispatching timed out',
        'threadName': 'unknown',
        'processName': 'com.PiliMax.android',
        'stackTrace': 'native trace',
        'status': 0,
        'importance': 100,
        'recentEvents': ['12:00:00.000  Route push /videoV'],
      }, systemInfo: 'current system');

      expect(report.source, CrashSource.androidExitInfo);
      expect(report.severity, CrashSeverity.fatal);
      expect(report.module, 'android_process');
      expect(report.reason, 'anr');
      expect(report.recentEvents, ['12:00:00.000  Route push /videoV']);
      expect(report.systemInfo, contains('Exit status: 0'));
      expect(report.systemInfo, contains('Exit importance: 100'));
      expect(report.isFatalCandidate, isTrue);
    });
  });
}
