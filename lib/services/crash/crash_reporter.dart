import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/services/crash/crash_breadcrumbs.dart';
import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:PiliMax/services/crash/crash_report.dart';
import 'package:PiliMax/services/crash/crash_report_filter.dart';
import 'package:PiliMax/services/crash/crash_report_store.dart';
import 'package:PiliMax/services/crash/native_crash_bridge.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class CrashReporter {
  static bool _installed = false;
  static FlutterExceptionHandler? _installedFlutterErrorHandler;
  static ErrorCallback? _installedPlatformErrorHandler;
  static final List<CrashReport> _bufferedReports = [];
  static final Map<String, _PersistedOccurrence> _persistedOccurrences = {};
  static const _dedupWindow = Duration(seconds: 3);
  static bool _nativeImportCompleted = false;
  static final Completer<void> _startupOverlayCompleted = Completer<void>();
  static final String sessionId =
      '$pid-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  static bool shouldIgnore(Object error, [StackTrace? stackTrace]) =>
      CrashReportFilter.shouldIgnore(error, stackTrace);

  static Future<CrashReport?> ensureInitialized() async {
    await CrashReportStore.ensureInitialized();
    _flushBufferedReports();
    try {
      CrashReportSystemInfo.update(await _buildSystemInfo());
    } catch (error) {
      CrashBreadcrumbs.record(
        'Crash system info unavailable: ${error.runtimeType}',
      );
      if (kDebugMode) debugPrint('Crash system info collection failed: $error');
    }
    // Native MethodChannel handlers are registered in MainActivity after runApp.
    // Only resolve Flutter-persisted pending reports here; native import is deferred.
    return resolvePendingForStartup();
  }

  /// Import Android JVM/exit-history staging after the engine channel is ready.
  static Future<CrashReport?> importNativeAndResolvePending() async {
    if (!_nativeImportCompleted) {
      try {
        await _importNativeReports();
        _nativeImportCompleted = true;
      } on MissingPluginException {
        // Channel not registered yet (before MainActivity.configureFlutterEngine).
        rethrow;
      }
    }
    return resolvePendingForStartup();
  }

  static Future<CrashReport?> resolvePendingForStartup() async {
    final pending = CrashReportStore.load();
    if (pending == null) return null;
    if (!pending.isFatalCandidate || pending.sessionId == sessionId) {
      await CrashReportStore.markSeen(pending.reportId);
      return null;
    }
    return pending;
  }

  static Future<void> waitForStartupOverlay() =>
      _startupOverlayCompleted.future;

  static void completeStartupOverlay() {
    if (!_startupOverlayCompleted.isCompleted) {
      _startupOverlayCompleted.complete();
    }
  }

  /// Clears both the Dart archive and native Android staging files. Native
  /// files are acknowledged only after the archive has been removed; a
  /// channel failure leaves them available for the next import attempt.
  static Future<void> clearHistory() async {
    await CrashReportStore.clear();
    try {
      final reports = await NativeCrashBridge.getPendingReports();
      final recordIds = [
        for (final report in reports)
          if (report['recordId'] is String) report['recordId'] as String,
      ];
      await NativeCrashBridge.acknowledgeReports(recordIds);
    } catch (_) {
      // Native cleanup is best-effort; a later launch can retry it.
    }
  }

  static void install({bool force = false}) {
    if (_installed && !force) return;
    if (_installed &&
        FlutterError.onError == _installedFlutterErrorHandler &&
        PlatformDispatcher.instance.onError == _installedPlatformErrorHandler) {
      return;
    }
    _installed = true;
    final installedFlutterErrorHandler = _installedFlutterErrorHandler;
    final installedPlatformErrorHandler = _installedPlatformErrorHandler;
    final currentFlutterErrorHandler = FlutterError.onError;
    final currentPlatformErrorHandler = PlatformDispatcher.instance.onError;
    final previousFlutterErrorHandler =
        currentFlutterErrorHandler == installedFlutterErrorHandler
        ? null
        : currentFlutterErrorHandler;
    final previousPlatformErrorHandler =
        currentPlatformErrorHandler == installedPlatformErrorHandler
        ? null
        : currentPlatformErrorHandler;

    late final FlutterExceptionHandler flutterHandler;
    flutterHandler = (details) {
      final stackModule = CrashModuleResolver.fromStack(details.stack);
      recordErrorSync(
        details.exception,
        details.stack,
        source: CrashSource.flutterFramework,
        severity: CrashSeverity.unhandled,
        module: stackModule == 'unknown' ? details.library : stackModule,
        operation: details.context?.toDescription() ?? '',
      );
      final previous = previousFlutterErrorHandler;
      if (previous != null && previous != flutterHandler) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    _installedFlutterErrorHandler = flutterHandler;
    FlutterError.onError = flutterHandler;

    late final ErrorCallback platformHandler;
    platformHandler = (error, stackTrace) {
      var handled = false;
      try {
        handled =
            previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
        return handled;
      } finally {
        recordErrorSync(
          error,
          stackTrace,
          source: CrashSource.platformDispatcher,
          severity: CrashSeverity.fromPlatformHandled(handled),
        );
      }
    };
    _installedPlatformErrorHandler = platformHandler;
    PlatformDispatcher.instance.onError = platformHandler;

    CrashBreadcrumbs.record('Crash reporter installed');
  }

  static CrashReport recordErrorSync(
    Object error,
    StackTrace? stackTrace, {
    CrashSource source = CrashSource.explicit,
    CrashSeverity severity = CrashSeverity.handled,
    String? module,
    String operation = '',
    String reason = '',
  }) {
    final route = CrashBreadcrumbNavigatorObserver.currentRoute;
    final ignored =
        !severity.isFatalCandidate &&
        _shouldIgnoreSafely(
          error,
          stackTrace,
        );
    final effectiveSeverity = ignored ? CrashSeverity.diagnostic : severity;
    final report = _buildReportSafely(
      error,
      stackTrace,
      source: source,
      severity: effectiveSeverity,
      sessionId: sessionId,
      module: module,
      operation: operation,
      route: route,
      reason: reason,
    );
    final typeName = _safeTypeName(error);
    try {
      CrashBreadcrumbs.record(
        ignored ? 'Crash ignored: $typeName' : 'Crash captured: $typeName',
      );
    } catch (_) {}
    if (!ignored) {
      _persistReport(report, makePending: severity.isFatalCandidate);
    }
    return report;
  }

  static Future<CrashReport> recordError(
    Object error,
    StackTrace? stackTrace, {
    CrashSource source = CrashSource.explicit,
    CrashSeverity severity = CrashSeverity.handled,
    String? module,
    String operation = '',
    String reason = '',
  }) {
    return Future.sync(
      () => recordErrorSync(
        error,
        stackTrace,
        source: source,
        severity: severity,
        module: module,
        operation: operation,
        reason: reason,
      ),
    );
  }

  static Future<void> _importNativeReports() async {
    try {
      // The native channel performs exit-history collection on its serial
      // background executor and completes this future without blocking Android's
      // main thread.
      final reports = await NativeCrashBridge.getPendingReports();
      final acknowledged = <String>[];
      for (final json in reports) {
        final recordId = json['recordId']?.toString();
        try {
          final report = CrashReport.fromNative(
            json,
            systemInfo: CrashReportSystemInfo.cached,
          );
          if (_isDuplicateGenericExit(report)) {
            if (recordId != null && recordId.isNotEmpty) {
              acknowledged.add(recordId);
            }
            continue;
          }
          final persisted = _persistReport(
            report,
            makePending: report.isFatalCandidate,
          );
          if (persisted && recordId != null && recordId.isNotEmpty) {
            acknowledged.add(recordId);
          }
        } catch (_) {
          continue;
        }
      }
      await NativeCrashBridge.acknowledgeReports(acknowledged);
    } on MissingPluginException {
      rethrow;
    } catch (error) {
      // Native crash import is best-effort; pending files remain for next launch.
      if (kDebugMode) {
        debugPrint('Native crash import failed: $error');
      }
    }
  }

  static bool _isDuplicateGenericExit(CrashReport report) {
    if (report.source != CrashSource.androidExitInfo ||
        (report.reason != 'java_crash' && report.reason != 'native_crash')) {
      return false;
    }
    final pending = CrashReportStore.load();
    if (pending == null || !pending.isFatalCandidate) return false;
    return (pending.crashedAtMillis - report.crashedAtMillis).abs() <= 10_000;
  }

  static void _flushBufferedReports() {
    while (_bufferedReports.isNotEmpty) {
      final report = _bufferedReports.first;
      try {
        if (_persistReport(report, makePending: report.isFatalCandidate)) {
          _bufferedReports.removeAt(0);
        } else {
          break;
        }
      } catch (error) {
        if (kDebugMode) debugPrint('Buffered crash report save failed: $error');
        break;
      }
    }
  }

  static void _bufferReport(CrashReport report) {
    final fingerprint = _fingerprint(report);
    final duplicateIndex = _bufferedReports.indexWhere(
      (item) => _fingerprint(item) == fingerprint,
    );
    if (duplicateIndex != -1) {
      final existing = _bufferedReports[duplicateIndex];
      if (_severityRank(report.severity) > _severityRank(existing.severity) ||
          _hasBetterAttribution(report, existing)) {
        _bufferedReports[duplicateIndex] = report;
      }
      return;
    }
    if (_bufferedReports.length >= 8) {
      final nonFatalIndex = _bufferedReports.indexWhere(
        (item) => !item.isFatalCandidate,
      );
      _bufferedReports.removeAt(nonFatalIndex == -1 ? 0 : nonFatalIndex);
    }
    _bufferedReports.add(report);
  }

  static bool _persistReport(
    CrashReport report, {
    required bool makePending,
  }) {
    final now = DateTime.now();
    _persistedOccurrences.removeWhere(
      (_, occurrence) => now.difference(occurrence.persistedAt) >= _dedupWindow,
    );
    final fingerprint = _fingerprint(report);
    final previous = _persistedOccurrences[fingerprint];
    if (previous != null &&
        now.difference(previous.persistedAt) < _dedupWindow &&
        !_shouldReplaceOccurrence(report, previous.report)) {
      return true;
    }

    try {
      if (!CrashReportStore.isInitialized) {
        _bufferReport(report);
        return false;
      }
      CrashReportStore.saveSync(report, makePending: makePending);
      // A dedup entry is recorded only after the synchronous write succeeds.
      _persistedOccurrences[fingerprint] = _PersistedOccurrence(
        report: previous?.report.mergeWith(report) ?? report,
        persistedAt: now,
      );
      return true;
    } catch (error) {
      _bufferReport(report);
      if (kDebugMode) {
        debugPrint(
          'Crash report save failed (${_safeTypeName(error)}): '
          '${_safeErrorText(error)}',
        );
      }
      return false;
    }
  }

  static bool _shouldReplaceOccurrence(CrashReport next, CrashReport previous) {
    return _severityRank(next.severity) > _severityRank(previous.severity) ||
        _hasBetterAttribution(next, previous);
  }

  static bool _hasBetterAttribution(CrashReport next, CrashReport previous) {
    final nextSource = _sourceRank(next.source);
    final previousSource = _sourceRank(previous.source);
    if (nextSource != previousSource) return nextSource > previousSource;
    return (previous.module == 'unknown' && next.module != 'unknown') ||
        (previous.operation.isEmpty && next.operation.isNotEmpty) ||
        (previous.route.isEmpty && next.route.isNotEmpty) ||
        (previous.reason.isEmpty && next.reason.isNotEmpty);
  }

  static String _fingerprint(CrashReport report) {
    final stack = report.stackTrace.length <= 4096
        ? report.stackTrace
        : report.stackTrace.substring(0, 4096);
    return sha256
        .convert(
          utf8.encode(
            '${report.exceptionType}\n${report.rootCause}\n$stack',
          ),
        )
        .toString();
  }

  static int _severityRank(CrashSeverity severity) => switch (severity) {
    CrashSeverity.fatal => 4,
    CrashSeverity.unhandled => 3,
    CrashSeverity.handled => 2,
    CrashSeverity.diagnostic => 1,
    CrashSeverity.unknown => 0,
  };

  static int _sourceRank(CrashSource source) => switch (source) {
    CrashSource.explicit => 6,
    CrashSource.flutterFramework => 5,
    CrashSource.platformDispatcher => 5,
    CrashSource.androidUncaught => 4,
    CrashSource.androidExitInfo => 4,
    CrashSource.catcher => 2,
    CrashSource.unknown => 0,
  };

  static CrashReport _buildReportSafely(
    Object error,
    StackTrace? stackTrace, {
    required CrashSource source,
    required CrashSeverity severity,
    required String sessionId,
    required String? module,
    required String operation,
    required String route,
    required String reason,
  }) {
    try {
      return CrashReport.fromError(
        error,
        stackTrace,
        source: source,
        severity: severity,
        sessionId: sessionId,
        module: module,
        operation: operation,
        route: route,
        reason: reason,
      );
    } catch (_) {
      final now = DateTime.now();
      return CrashReport(
        reportId: '${now.millisecondsSinceEpoch}',
        crashedAtMillis: now.millisecondsSinceEpoch,
        crashedAtText: now.toIso8601String(),
        exceptionType: _safeTypeName(error),
        rootCause: 'Crash report generation failed',
        threadName: 'main',
        processName: 'pid:$pid',
        systemInfo: CrashReportSystemInfo.cached,
        stackTrace: 'Crash report generation failed',
        source: source,
        severity: severity,
        sessionId: sessionId,
        module: module ?? 'unknown',
        operation: operation,
        route: route,
        reason: reason,
      ).normalized();
    }
  }

  static bool _shouldIgnoreSafely(Object error, StackTrace? stackTrace) {
    try {
      return shouldIgnore(error, stackTrace);
    } catch (_) {
      return false;
    }
  }

  static String _safeTypeName(Object? value) {
    try {
      return value.runtimeType.toString();
    } catch (_) {
      return 'UnknownError';
    }
  }

  static String _safeErrorText(Object? value) {
    try {
      return value.toString();
    } catch (_) {
      return 'unavailable';
    }
  }

  static Future<String> _buildSystemInfo() async {
    final lines = <String>[
      'App version: ${BuildConfig.versionName} (${BuildConfig.versionCode})',
      'Build time: ${BuildConfig.buildTime}',
      'Commit: ${BuildConfig.commitHash}',
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Locale: ${Platform.localeName}',
      'Memory: ${ProcessInfo.currentRss ~/ _bytesPerMebibyte} MiB used / '
          '${ProcessInfo.maxRss ~/ _bytesPerMebibyte} MiB max',
    ];
    final deviceInfo = await _deviceInfo();
    if (deviceInfo.isNotEmpty) {
      lines.addAll(deviceInfo);
    }
    return lines.join('\n');
  }

  static Future<List<String>> _deviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return [
          'Device: ${info.manufacturer} ${info.model}',
          'Android: ${info.version.release} (SDK ${info.version.sdkInt})',
          'ABI: ${info.supportedAbis.join(', ')}',
        ];
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return [
          'Device model: ${info.model}',
          'System: ${info.systemName} ${info.systemVersion}',
        ];
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return [
          'Device model: ${info.model}',
          'Kernel: ${info.kernelVersion}',
        ];
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return [
          'Windows build: ${info.buildNumber}',
        ];
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return [
          'Device: ${info.prettyName}',
        ];
      }
    } catch (e) {
      return ['Device info unavailable: ${_safeTypeName(e)}'];
    }
    return const [];
  }

  static const _bytesPerMebibyte = 1024 * 1024;
}

class _PersistedOccurrence {
  const _PersistedOccurrence({required this.report, required this.persistedAt});

  final CrashReport report;
  final DateTime persistedAt;
}
