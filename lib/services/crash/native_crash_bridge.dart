import 'dart:io';

import 'package:flutter/services.dart';

abstract final class NativeCrashBridge {
  static const _channel = MethodChannel('com.PiliMax.android/native_crash');

  static Future<List<Map<String, dynamic>>> getPendingReports() async {
    if (!Platform.isAndroid) return const [];
    final reports = await _channel.invokeListMethod<Object?>(
      'getPendingReports',
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
