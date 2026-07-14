import 'dart:async';
import 'dart:io';
import 'dart:ui'
    show FramePhase, FrameTiming, PlatformDispatcher, TimingsCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

enum VideoTransitionDiagnosticKind {
  entry('卡片展开'),
  detailReveal('骨架切换'),
  predictiveBack('预测性返回'),
  programmaticBack('普通返回');

  const VideoTransitionDiagnosticKind(this.label);

  final String label;
}

final class VideoTransitionDisplaySnapshot {
  const VideoTransitionDisplaySnapshot({
    this.flutterRefreshRate,
    this.androidAppRefreshRate,
    this.androidModeRefreshRate,
    this.androidActiveMode,
    this.androidPreferredMode,
    this.preferredDisplayModeId,
  });

  final double? flutterRefreshRate;
  final double? androidAppRefreshRate;
  final double? androidModeRefreshRate;
  final String? androidActiveMode;
  final String? androidPreferredMode;
  final int? preferredDisplayModeId;

  VideoTransitionDisplaySnapshot copyWith({
    double? flutterRefreshRate,
    double? androidAppRefreshRate,
    double? androidModeRefreshRate,
    String? androidActiveMode,
    String? androidPreferredMode,
    int? preferredDisplayModeId,
  }) => VideoTransitionDisplaySnapshot(
    flutterRefreshRate: flutterRefreshRate ?? this.flutterRefreshRate,
    androidAppRefreshRate: androidAppRefreshRate ?? this.androidAppRefreshRate,
    androidModeRefreshRate:
        androidModeRefreshRate ?? this.androidModeRefreshRate,
    androidActiveMode: androidActiveMode ?? this.androidActiveMode,
    androidPreferredMode: androidPreferredMode ?? this.androidPreferredMode,
    preferredDisplayModeId:
        preferredDisplayModeId ?? this.preferredDisplayModeId,
  );

  String get compactDescription => [
    'Flutter ${_formatHz(flutterRefreshRate)}',
    '应用 ${_formatHz(androidAppRefreshRate)}',
    '物理 ${_formatHz(androidModeRefreshRate)}',
  ].join(' · ');

  static String _formatHz(double? value) => value == null
      ? '-- Hz'
      : '${value.toStringAsFixed(value.roundToDouble() == value ? 0 : 1)} Hz';
}

final class VideoTransitionDiagnosticReport {
  const VideoTransitionDiagnosticReport({
    required this.kind,
    required this.outcome,
    required this.startedAt,
    required this.elapsed,
    required this.expectedDuration,
    required this.startDisplay,
    required this.endDisplay,
    required this.frameCount,
    required this.renderedFps,
    required this.effectiveFps,
    required this.firstFrameDelayMs,
    required this.frameIntervalP50Ms,
    required this.frameIntervalP95Ms,
    required this.buildP50Ms,
    required this.buildP95Ms,
    required this.buildP99Ms,
    required this.rasterP50Ms,
    required this.rasterP95Ms,
    required this.rasterP99Ms,
    required this.totalP95Ms,
    required this.overBudgetBuildFrames,
    required this.overBudgetRasterFrames,
    required this.longFrameIntervals,
    required this.inputEventCount,
    required this.inputEventRate,
  });

  final VideoTransitionDiagnosticKind kind;
  final String outcome;
  final DateTime startedAt;
  final Duration elapsed;
  final Duration? expectedDuration;
  final VideoTransitionDisplaySnapshot startDisplay;
  final VideoTransitionDisplaySnapshot endDisplay;
  final int frameCount;
  final double? renderedFps;
  final double? effectiveFps;
  final double? firstFrameDelayMs;
  final double? frameIntervalP50Ms;
  final double? frameIntervalP95Ms;
  final double? buildP50Ms;
  final double? buildP95Ms;
  final double? buildP99Ms;
  final double? rasterP50Ms;
  final double? rasterP95Ms;
  final double? rasterP99Ms;
  final double? totalP95Ms;
  final int overBudgetBuildFrames;
  final int overBudgetRasterFrames;
  final int longFrameIntervals;
  final int inputEventCount;
  final double? inputEventRate;

  String get title => '${kind.label} · ${_fps(renderedFps)} FPS';

  String get subtitle {
    final effectiveText = effectiveFps == null
        ? ''
        : ' · 有效 ${_fps(effectiveFps)} FPS';
    final eventText = inputEventRate == null
        ? ''
        : ' · 手势 ${_fps(inputEventRate)} Hz';
    return '${elapsed.inMilliseconds} ms · $frameCount 帧$effectiveText$eventText';
  }

  String toExportText() {
    final expected = expectedDuration == null
        ? '--'
        : '${expectedDuration!.inMilliseconds} ms';
    return <String>[
      '[${startedAt.toIso8601String()}] ${kind.label} ($outcome)',
      '采样时长: ${elapsed.inMilliseconds} ms；预期动画: $expected',
      '显示-开始: ${startDisplay.compactDescription}',
      '显示-结束: ${endDisplay.compactDescription}',
      'Android active: ${endDisplay.androidActiveMode ?? '--'}',
      'Android preferred: ${endDisplay.androidPreferredMode ?? '--'}',
      'preferredDisplayModeId: ${endDisplay.preferredDisplayModeId ?? '--'}',
      '渲染: $frameCount 帧；${_fps(renderedFps)} FPS',
      '有效 FPS（完整采样窗口）: ${_fps(effectiveFps)}',
      '首帧完成延迟（近似）: ${_ms(firstFrameDelayMs)}',
      '帧间隔 P50/P95: ${_ms(frameIntervalP50Ms)} / ${_ms(frameIntervalP95Ms)}',
      'Build P50/P95/P99: ${_ms(buildP50Ms)} / ${_ms(buildP95Ms)} / ${_ms(buildP99Ms)}',
      'Raster P50/P95/P99: ${_ms(rasterP50Ms)} / ${_ms(rasterP95Ms)} / ${_ms(rasterP99Ms)}',
      'Total P95: ${_ms(totalP95Ms)}',
      '超预算 Build/Raster: $overBudgetBuildFrames / $overBudgetRasterFrames',
      '长帧间隔: $longFrameIntervals',
      '手势事件: $inputEventCount；${_fps(inputEventRate)} Hz',
      '构建模式: ${VideoTransitionDiagnostics.buildModeLabel}',
      '渲染后端: ${VideoTransitionDiagnostics.rendererLabel}',
    ].join('\n');
  }

  static String _fps(double? value) =>
      value == null ? '--' : value.toStringAsFixed(1);

  static String _ms(double? value) =>
      value == null ? '--' : '${value.toStringAsFixed(2)} ms';
}

abstract final class VideoTransitionDiagnostics {
  static const bool available =
      kDebugMode || bool.fromEnvironment('PILIMAX_TRANSITION_DIAGNOSTICS');
  static const String rendererLabel = String.fromEnvironment(
    'PILIMAX_RENDERER',
    defaultValue: '未标记',
  );
  static const MethodChannel _appChannel = MethodChannel('PiliMax');
  static const Duration _timingDrainDelay = Duration(milliseconds: 1200);
  static const int _maxReports = 30;

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(available);
  static final ValueNotifier<List<VideoTransitionDiagnosticReport>> reports =
      ValueNotifier<List<VideoTransitionDiagnosticReport>>(
        const <VideoTransitionDiagnosticReport>[],
      );
  static final ValueNotifier<VideoTransitionDisplaySnapshot?> currentDisplay =
      ValueNotifier<VideoTransitionDisplaySnapshot?>(null);
  static final ValueNotifier<int> activeCaptureCount = ValueNotifier<int>(0);

  static final Map<int, _VideoTransitionCapture> _captures = {};
  static int _nextCaptureId = 0;

  static int? begin(
    VideoTransitionDiagnosticKind kind, {
    Duration? expectedDuration,
  }) {
    if (!available || !enabled.value) {
      return null;
    }
    final id = ++_nextCaptureId;
    final cachedDisplay = currentDisplay.value;
    final capture = _VideoTransitionCapture(
      id: id,
      kind: kind,
      expectedDuration: expectedDuration,
      startFrameTimeMicros: _frameBoundary(isStart: true),
      startDisplay: (cachedDisplay ?? const VideoTransitionDisplaySnapshot())
          .copyWith(flutterRefreshRate: _flutterRefreshRate),
    );
    capture.timingsCallback = capture.addTimings;
    _captures[id] = capture;
    SchedulerBinding.instance.addTimingsCallback(capture.timingsCallback);
    _updateActiveCount();
    return id;
  }

  static void recordInputEvent(int? captureId) {
    final capture = captureId == null ? null : _captures[captureId];
    if (capture == null || capture.hasEnded) {
      return;
    }
    capture.inputEventMicros.add(capture.stopwatch.elapsedMicroseconds);
  }

  static void finish(int? captureId, {required String outcome}) {
    final capture = captureId == null ? null : _captures[captureId];
    if (capture == null || capture.hasEnded) {
      return;
    }
    capture
      ..outcome = outcome
      ..endedAtMicros = capture.stopwatch.elapsedMicroseconds
      ..endFrameTimeMicros = _frameBoundary(isStart: false);
    _updateActiveCount();
    capture.finalizeTimer = Timer(
      _timingDrainDelay,
      () => unawaited(_finalize(capture)),
    );
  }

  static void setEnabled(bool value) {
    enabled.value = available && value;
    if (enabled.value) {
      return;
    }
    for (final capture in _captures.values.toList(growable: false)) {
      finish(capture.id, outcome: 'disabled');
    }
  }

  static void clearReports() {
    reports.value = const <VideoTransitionDiagnosticReport>[];
  }

  static String exportText() =>
      reports.value.map((report) => report.toExportText()).join('\n\n');

  static String get buildModeLabel => switch ((kReleaseMode, kProfileMode)) {
    (true, _) => 'RELEASE/AOT',
    (_, true) => 'PROFILE/AOT',
    _ => 'DEBUG/JIT',
  };

  static String get environmentLabel => '$buildModeLabel · $rendererLabel';

  static Future<VideoTransitionDisplaySnapshot> refreshDisplaySnapshot() async {
    var snapshot = VideoTransitionDisplaySnapshot(
      flutterRefreshRate: _flutterRefreshRate,
    );
    if (Platform.isAndroid) {
      try {
        final native = await _appChannel.invokeMapMethod<String, dynamic>(
          'getDisplayRefreshRates',
        );
        snapshot = snapshot.copyWith(
          androidAppRefreshRate: _asDouble(native?['appRefreshRate']),
          androidModeRefreshRate: _asDouble(native?['modeRefreshRate']),
          preferredDisplayModeId: native?['preferredDisplayModeId'] as int?,
        );
      } catch (_) {}
      try {
        final active = await FlutterDisplayMode.active;
        snapshot = snapshot.copyWith(
          androidActiveMode: active.toString(),
          androidModeRefreshRate: active.refreshRate,
        );
      } catch (_) {}
      try {
        final preferred = await FlutterDisplayMode.preferred;
        snapshot = snapshot.copyWith(
          androidPreferredMode: preferred.toString(),
        );
      } catch (_) {}
    }
    currentDisplay.value = snapshot;
    return snapshot;
  }

  static double? get _flutterRefreshRate {
    final refreshRate =
        PlatformDispatcher.instance.implicitView?.display.refreshRate;
    return refreshRate == null || refreshRate <= 0 ? null : refreshRate;
  }

  static double? _asDouble(Object? value) => switch (value) {
    final num number => number.toDouble(),
    _ => null,
  };

  static int _frameBoundary({required bool isStart}) {
    final binding = SchedulerBinding.instance;
    final rawMicros = binding.currentSystemFrameTimeStamp.inMicroseconds;
    return isStart &&
            (binding.schedulerPhase == SchedulerPhase.idle ||
                binding.schedulerPhase == SchedulerPhase.postFrameCallbacks)
        ? rawMicros + 1
        : rawMicros;
  }

  static Future<void> _finalize(_VideoTransitionCapture capture) async {
    capture.finalizeTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(capture.timingsCallback);
    if (!identical(_captures.remove(capture.id), capture)) {
      return;
    }
    capture.stopwatch.stop();
    final endDisplay = await refreshDisplaySnapshot();
    final report = capture.buildReport(endDisplay);
    final next = <VideoTransitionDiagnosticReport>[
      report,
      ...reports.value,
    ];
    if (next.length > _maxReports) {
      next.removeRange(_maxReports, next.length);
    }
    reports.value = List.unmodifiable(next);
    _updateActiveCount();
    debugPrint('[VideoTransitionDiagnostics]\n${report.toExportText()}');
  }

  static void _updateActiveCount() {
    activeCaptureCount.value = _captures.values
        .where((capture) => !capture.hasEnded)
        .length;
  }
}

final class _VideoTransitionCapture {
  _VideoTransitionCapture({
    required this.id,
    required this.kind,
    required this.expectedDuration,
    required this.startFrameTimeMicros,
    required this.startDisplay,
  }) : startedAt = DateTime.now(),
       stopwatch = Stopwatch()..start();

  final int id;
  final VideoTransitionDiagnosticKind kind;
  final Duration? expectedDuration;
  final int startFrameTimeMicros;
  final VideoTransitionDisplaySnapshot startDisplay;
  final DateTime startedAt;
  final Stopwatch stopwatch;
  final List<FrameTiming> timings = [];
  final List<int> inputEventMicros = [];
  late final TimingsCallback timingsCallback;
  Timer? finalizeTimer;
  int? endedAtMicros;
  int? endFrameTimeMicros;
  String outcome = 'unknown';

  bool get hasEnded => endedAtMicros != null;

  void addTimings(List<FrameTiming> values) => timings.addAll(values);

  VideoTransitionDiagnosticReport buildReport(
    VideoTransitionDisplaySnapshot endDisplay,
  ) {
    final elapsedMicros = endedAtMicros ?? stopwatch.elapsedMicroseconds;
    final elapsed = Duration(microseconds: elapsedMicros);
    final effectiveStartDisplay = startDisplay.copyWith(
      flutterRefreshRate:
          startDisplay.flutterRefreshRate ?? endDisplay.flutterRefreshRate,
    );
    final rawBudgetHz =
        effectiveStartDisplay.flutterRefreshRate ??
        effectiveStartDisplay.androidAppRefreshRate ??
        effectiveStartDisplay.androidModeRefreshRate ??
        60;
    final budgetHz = rawBudgetHz.isFinite && rawBudgetHz > 0
        ? rawBudgetHz
        : 60.0;
    final budgetMicros = 1000000 / budgetHz;

    final uniqueByBuildStart = <int, FrameTiming>{
      for (final timing in timings)
        timing.timestampInMicroseconds(FramePhase.buildStart): timing,
    };
    final sorted = uniqueByBuildStart.values.toList(growable: false)
      ..sort(
        (a, b) => a
            .timestampInMicroseconds(FramePhase.buildStart)
            .compareTo(b.timestampInMicroseconds(FramePhase.buildStart)),
      );
    final selected = sorted
        .where((timing) {
          final buildStart = timing.timestampInMicroseconds(
            FramePhase.buildStart,
          );
          return buildStart >= startFrameTimeMicros &&
              buildStart <= (endFrameTimeMicros ?? startFrameTimeMicros);
        })
        .toList(growable: false);

    final frameIntervalsMicros = <double>[];
    for (var index = 1; index < selected.length; index++) {
      final interval =
          selected[index].timestampInMicroseconds(FramePhase.buildStart) -
          selected[index - 1].timestampInMicroseconds(FramePhase.buildStart);
      if (interval > 0) {
        frameIntervalsMicros.add(interval.toDouble());
      }
    }
    final buildMicros = selected
        .map((timing) => timing.buildDuration.inMicroseconds.toDouble())
        .toList(growable: false);
    final rasterMicros = selected
        .map((timing) => timing.rasterDuration.inMicroseconds.toDouble())
        .toList(growable: false);
    final totalMicros = selected
        .map((timing) => timing.totalSpan.inMicroseconds.toDouble())
        .toList(growable: false);
    final renderedFps = frameIntervalsMicros.isEmpty
        ? null
        : 1000000 / _average(frameIntervalsMicros);
    final effectiveFps = elapsedMicros <= 0 || selected.isEmpty
        ? null
        : selected.length * 1000000 / elapsedMicros;
    final firstFrameDelayMicros = selected.isEmpty
        ? null
        : selected.first.timestampInMicroseconds(FramePhase.rasterFinish) -
              startFrameTimeMicros;
    final firstFrameDelayMs = firstFrameDelayMicros == null
        ? null
        : (firstFrameDelayMicros < 0 ? 0 : firstFrameDelayMicros) / 1000;
    final eventSpan = inputEventMicros.length < 2
        ? 0
        : inputEventMicros.last - inputEventMicros.first;
    final eventRate = eventSpan <= 0
        ? null
        : (inputEventMicros.length - 1) * 1000000 / eventSpan;

    return VideoTransitionDiagnosticReport(
      kind: kind,
      outcome: outcome,
      startedAt: startedAt,
      elapsed: elapsed,
      expectedDuration: expectedDuration,
      startDisplay: effectiveStartDisplay,
      endDisplay: endDisplay,
      frameCount: selected.length,
      renderedFps: renderedFps,
      effectiveFps: effectiveFps,
      firstFrameDelayMs: firstFrameDelayMs,
      frameIntervalP50Ms: _percentileMs(frameIntervalsMicros, 0.50),
      frameIntervalP95Ms: _percentileMs(frameIntervalsMicros, 0.95),
      buildP50Ms: _percentileMs(buildMicros, 0.50),
      buildP95Ms: _percentileMs(buildMicros, 0.95),
      buildP99Ms: _percentileMs(buildMicros, 0.99),
      rasterP50Ms: _percentileMs(rasterMicros, 0.50),
      rasterP95Ms: _percentileMs(rasterMicros, 0.95),
      rasterP99Ms: _percentileMs(rasterMicros, 0.99),
      totalP95Ms: _percentileMs(totalMicros, 0.95),
      overBudgetBuildFrames: buildMicros
          .where((duration) => duration > budgetMicros)
          .length,
      overBudgetRasterFrames: rasterMicros
          .where((duration) => duration > budgetMicros)
          .length,
      longFrameIntervals: frameIntervalsMicros
          .where((duration) => duration > budgetMicros * 1.5)
          .length,
      inputEventCount: inputEventMicros.length,
      inputEventRate: eventRate,
    );
  }

  static double _average(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  static double? _percentileMs(List<double> values, double percentile) {
    if (values.isEmpty) {
      return null;
    }
    final sorted = values.toList(growable: false)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index] / 1000;
  }
}
