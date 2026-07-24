import 'package:PiliMax/services/crash/crash_reporter.dart';
import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:catcher_2/catcher_2.dart';

class CrashReportHandler extends ReportHandler {
  @override
  Future<bool> handle(Report report) => Future.sync(() {
    final stackTrace = report.stackTrace;
    CrashReporter.recordErrorSync(
      report.error,
      switch (stackTrace) {
        StackTrace() => stackTrace,
        String() when stackTrace.trim().isNotEmpty => StackTrace.fromString(
          stackTrace,
        ),
        _ => null,
      },
      source: CrashSource.catcher,
      severity: CrashSeverity.handled,
    );
    return true;
  });
}
