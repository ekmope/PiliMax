import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class NativeCrashBridge {
  static const _channel = MethodChannel('com.PiliMax.android/native_crash');
  static Map<String, Object?>? _lastPlaybackState;

  static void recordPlaybackState(Map<String, Object?> state) {
    if (!Platform.isAndroid || mapEquals(state, _lastPlaybackState)) return;
    _lastPlaybackState = Map.of(state);
    unawaited(
      _channel.invokeMethod<void>('recordPlaybackState', state).catchError((
        Object _,
      ) {
        // A missing/unavailable native bridge must not affect playback.
        _lastPlaybackState = null;
      }),
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingReports({
    int? limit,
  }) async {
    if (!Platform.isAndroid) return const [];
    final reports = await _channel.invokeListMethod<Object?>(
      'getPendingReports',
      limit == null ? null : {'limit': limit},
    );
    return [
      for (final report in reports ?? const [])
        if (report is Map)
          report.map((key, value) => MapEntry(key.toString(), value)),
    ];
  }

  static Future<void> acknowledgeReports(List<String> recordIds) async {
    if (!Platform.isAndroid || recordIds.isEmpty) return;
    await _channel.invokeMethod<void>('acknowledgeReports', {
      'recordIds': recordIds,
    });
  }
}
