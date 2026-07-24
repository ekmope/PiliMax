import 'package:PiliMax/services/crash/crash_report.dart';
import 'package:PiliMax/services/crash/crash_report_archive.dart';
import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashReportArchive', () {
    test('migrates a legacy single report and keeps it pending', () {
      final report = _report(1);

      final archive = CrashReportArchive.fromJson(report.toJson());

      expect(archive.reports.single.reportId, report.reportId);
      expect(archive.pendingReport?.reportId, report.reportId);
    });

    test('marks a startup report seen without deleting history', () {
      final report = _report(1);
      final archive = const CrashReportArchive.empty().add(report);

      final updated = archive.markSeen(report.reportId);

      expect(updated.pendingReport, isNull);
      expect(updated.reports, [report]);
    });

    test('retains handled reports without making them startup pending', () {
      final report = _report(
        1,
        severity: CrashSeverity.handled,
      );

      final archive = const CrashReportArchive.empty().add(
        report,
        makePending: false,
      );

      expect(archive.pendingReport, isNull);
      expect(archive.reports, [report]);
    });

    test('deduplicates repeated callbacks for the same occurrence', () {
      final first = _report(1000);
      final duplicate = _report(1500, reportId: 'duplicate');

      final archive = const CrashReportArchive.empty()
          .add(first)
          .add(duplicate);

      expect(archive.reports, hasLength(1));
      expect(archive.reports.single.reportId, first.reportId);
      expect(archive.reports.single.crashedAtMillis, first.crashedAtMillis);
      expect(archive.pendingReport?.reportId, first.reportId);
    });

    test('upgrades duplicate handled report to fatal attribution', () {
      final handled = _report(
        1000,
        severity: CrashSeverity.handled,
      );
      final fatal = _report(
        1500,
        reportId: 'fatal-copy',
        severity: CrashSeverity.fatal,
      );

      final archive = const CrashReportArchive.empty()
          .add(handled, makePending: false)
          .add(fatal);

      expect(archive.reports, hasLength(1));
      expect(archive.reports.single.severity, CrashSeverity.fatal);
      expect(archive.pendingReport?.severity, CrashSeverity.fatal);
    });

    test(
      'merges replicated archives without letting an old copy shadow data',
      () {
        final older = _report(1);
        final newer = _report(2, rootCause: 'newer');

        final merged = CrashReportArchive.mergeReplicas([
          const CrashReportArchive.empty().add(older),
          const CrashReportArchive.empty().add(newer),
        ]);

        expect(merged.reports, [newer, older]);
        expect(merged.pendingReport, newer);
      },
    );

    test('retains only the newest bounded history', () {
      var archive = const CrashReportArchive.empty();
      for (var i = 0; i < CrashReportArchive.maxReports + 2; i++) {
        archive = archive.add(_report(i, rootCause: 'failure-$i'));
      }

      expect(archive.reports, hasLength(CrashReportArchive.maxReports));
      expect(archive.reports.first.crashedAtMillis, 21);
      expect(archive.reports.last.crashedAtMillis, 2);
    });

    test('does not evict an unread fatal report behind handled history', () {
      final fatal = _report(1, severity: CrashSeverity.fatal);
      var archive = const CrashReportArchive.empty().add(fatal);
      for (var i = 2; i <= CrashReportArchive.maxReports + 2; i++) {
        archive = archive.add(
          _report(i, rootCause: 'handled-$i', severity: CrashSeverity.handled),
          makePending: false,
        );
      }

      expect(archive.pendingReport, fatal);
      expect(archive.reports, contains(fatal));
      expect(archive.reports, hasLength(CrashReportArchive.maxReports));
    });

    test(
      'keeps a newer pending report when importing an older fatal event',
      () {
        final newer = _report(2000, severity: CrashSeverity.fatal);
        final older = _report(
          1000,
          rootCause: 'older failure',
          severity: CrashSeverity.fatal,
        );

        final archive = const CrashReportArchive.empty().add(newer).add(older);

        expect(archive.pendingReport, newer);
      },
    );

    test(
      'imports history-only reports without startup pending',
      () {
        final historyOnly = _report(
          3000,
          reportId: 'history-a1b2c3d4',
          rootCause: 'boom',
          severity: CrashSeverity.fatal,
        );

        final archive = const CrashReportArchive.empty().add(
          historyOnly,
          makePending: false,
        );

        expect(archive.reports, [historyOnly]);
        expect(archive.pendingReport, isNull);
      },
    );

    test(
      'does not replace startup pending with a history-only import',
      () {
        final exitPending = _report(
          2000,
          reportId: 'exit-pending',
          severity: CrashSeverity.fatal,
        );
        final laterHistory = _report(
          4000,
          reportId: 'later-history',
          rootCause: 'later failure',
          severity: CrashSeverity.fatal,
        );

        final archive = const CrashReportArchive.empty()
            .add(exitPending)
            .add(laterHistory, makePending: false);

        expect(archive.pendingReport, exitPending);
        expect(archive.reports, containsAll([exitPending, laterHistory]));
      },
    );
  });
}

CrashReport _report(
  int crashedAtMillis, {
  String? reportId,
  String rootCause = 'failure',
  CrashSeverity severity = CrashSeverity.unhandled,
}) {
  return CrashReport(
    reportId: reportId ?? 'report-$crashedAtMillis',
    crashedAtMillis: crashedAtMillis,
    crashedAtText: crashedAtMillis.toString(),
    exceptionType: 'StateError',
    rootCause: rootCause,
    threadName: 'main',
    processName: 'pid:1',
    systemInfo: 'test',
    stackTrace: 'stack',
    source: CrashSource.explicit,
    severity: severity,
    sessionId: 'test-session',
  );
}
