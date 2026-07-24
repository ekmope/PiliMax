enum CrashSource {
  flutterFramework('flutter_framework', 'Flutter 框架'),
  platformDispatcher('platform_dispatcher', 'Dart 根 Isolate'),
  catcher('catcher', 'Catcher'),
  explicit('explicit', '应用主动上报'),
  androidUncaught('android_uncaught', 'Android JVM'),
  androidExitInfo('android_exit_info', 'Android 进程退出'),
  unknown('unknown', '未知来源');

  const CrashSource(this.value, this.label);

  final String value;
  final String label;

  static CrashSource parse(Object? value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => unknown,
  );
}

enum CrashSeverity {
  fatal('fatal', '致命'),
  unhandled('unhandled', '未处理'),
  handled('handled', '已处理'),
  diagnostic('diagnostic', '诊断'),
  unknown('unknown', '未知');

  const CrashSeverity(this.value, this.label);

  final String value;
  final String label;

  bool get isFatalCandidate => this == fatal;

  static CrashSeverity fromPlatformHandled(bool handled) =>
      handled ? unhandled : fatal;

  static CrashSeverity parse(Object? value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => unknown,
  );
}

abstract final class CrashModuleResolver {
  static String fromStack(StackTrace? stackTrace) {
    if (stackTrace == null) return 'unknown';
    for (final line in stackTrace.toString().split('\n')) {
      final match = _packagePath.firstMatch(line);
      if (match == null) continue;
      final path = match.group(1)!.split('/');
      return path.take(path.length >= 2 ? 2 : 1).join('/');
    }
    return 'unknown';
  }

  static final _packagePath = RegExp(r'package:PiliMax/([^:)\s]+)');
}
