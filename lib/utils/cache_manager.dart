import 'dart:io' show Directory, File;

import 'package:PiliMax/pilimax/services/crash/crash_context.dart';
import 'package:PiliMax/pilimax/services/crash/crash_reporter.dart';
import 'package:PiliMax/pilimax/utils/app_temporary_files.dart';
import 'package:PiliMax/pilimax/utils/cache_policy.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

abstract final class CacheManager {
  static late final DefaultCacheManager manager;
  static final CacheClearCoordinator _clearCoordinator =
      CacheClearCoordinator();

  static Future<void> ensureInitialized() => DefaultCacheManager.init(
    maxNrOfCacheLength: Pref.maxCacheSize.toInt(),
  ).then((i) => manager = i);

  // 获取缓存目录
  @pragma('vm:notify-debugger-on-exception')
  static Future<int> loadApplicationCache() async {
    var total = 0;
    try {
      total += manager.getTotalLength();
    } catch (_, stackTrace) {
      _recordCacheError(
        stackTrace,
        operation: 'size.networkImages',
        reason: 'network_cache_size_failed',
      );
    }
    try {
      final directory = AppTemporaryFiles.directory(AppTemporaryOwner.cache);
      if (directory.existsSync()) {
        total += await getTotalSizeOfFilesInDir(directory);
      }
    } catch (_, stackTrace) {
      _recordCacheError(
        stackTrace,
        operation: 'size.appCache',
        reason: 'app_cache_size_failed',
      );
    }
    return total;
  }

  // 循环计算文件的大小
  @pragma('vm:notify-debugger-on-exception')
  static Future<int> getTotalSizeOfFilesInDir(final Directory file) async {
    int total = 0;
    await for (final child in file.list(recursive: true, followLinks: false)) {
      if (child is File) {
        total += await child.length();
      }
    }
    return total;
  }

  // 缓存大小格式转换
  static String formatSize(num value) {
    const unitArr = ['B', 'K', 'M', 'G', 'T', 'P'];
    int index = 0;
    while (value >= 1024) {
      index++;
      value = value / 1024;
    }
    String size = value.toStringAsFixed(2);
    return size + (unitArr.elementAtOrNull(index) ?? '');
  }

  // 仅清理由 PiliMax 明确拥有的缓存，不遍历系统临时目录。
  @pragma('vm:notify-debugger-on-exception')
  static Future<CacheClearResult> clearLibraryCache() => _clearCoordinator.run(
    {
      CacheClearTarget.networkImages: manager.emptyCache,
      CacheClearTarget.appCache: () =>
          AppTemporaryFiles.clear(AppTemporaryOwner.cache),
    },
    onError: (target, _, stackTrace) => _recordCacheError(
      stackTrace,
      operation: 'clear.${target.name}',
      reason: 'cache_clear_failed',
    ),
  );

  static Future<void> clearExpiredCache() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastClearTime = GStorage.localCache.get(
        LocalCacheKey.lastAutoClearCacheTime,
        defaultValue: 0,
      );
      final decision = AutoCacheClearPolicy.decide(
        enabled: Pref.autoClearCache,
        nowMilliseconds: now,
        lastClearMilliseconds: lastClearTime,
        periodDays: Pref.autoClearCachePeriod,
      );
      switch (decision) {
        case AutoCacheClearDecision.initializeBaseline ||
            AutoCacheClearDecision.resetClockBaseline:
          await GStorage.localCache.put(
            LocalCacheKey.lastAutoClearCacheTime,
            now,
          );
          return;
        case AutoCacheClearDecision.clear:
          final result = await clearLibraryCache();
          if (result.allSucceeded) {
            await GStorage.localCache.put(
              LocalCacheKey.lastAutoClearCacheTime,
              now,
            );
          }
          return;
        case AutoCacheClearDecision.disabled || AutoCacheClearDecision.notDue:
          return;
      }
    } catch (_, stackTrace) {
      _recordCacheError(
        stackTrace,
        operation: 'clear.auto',
        reason: 'automatic_cache_clear_failed',
      );
    }
  }

  static void _recordCacheError(
    StackTrace stackTrace, {
    required String operation,
    required String reason,
  }) {
    try {
      CrashReporter.recordErrorSync(
        StateError('Cache operation failed'),
        stackTrace,
        severity: CrashSeverity.handled,
        module: 'cache',
        operation: operation,
        reason: reason,
      );
    } catch (_) {}
  }
}
