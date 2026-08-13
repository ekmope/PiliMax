import 'dart:async';

import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/pilimax/utils/android/android_mmkv_box.dart';
import 'package:PiliMax/pilimax/utils/android/android_mmkv_recovery.dart';
import 'package:flutter/material.dart';

typedef AndroidMmkvRetryCallback = Future<void> Function();
typedef AndroidMmkvResetCallback =
    Future<void> Function(AndroidMmkvMigrationException failure);
typedef AndroidMmkvRecoveryErrorCallback =
    void Function(Object error, StackTrace stackTrace, String operation);

final class AndroidMmkvRecoveryController extends ChangeNotifier {
  AndroidMmkvRecoveryController({
    required this.failure,
    required this.retryStorage,
    required this.resetStorage,
    required this.closeApplication,
    required this.reportCallbackError,
  });

  final AndroidMmkvRetryCallback retryStorage;
  final AndroidMmkvResetCallback resetStorage;
  final VoidCallback closeApplication;
  final AndroidMmkvRecoveryErrorCallback reportCallbackError;
  final Completer<void> _recovered = Completer<void>();

  AndroidMmkvMigrationException failure;
  bool _busy = false;
  bool _fatal = false;
  String? _message;

  bool get busy => _busy;
  bool get fatal => _fatal;
  String? get message => _message;
  Future<void> get recovered => _recovered.future;

  Future<void> retry() => _run(reset: false);

  Future<void> backupResetAndRetry() => _run(reset: true);

  Future<void> _run({required bool reset}) async {
    if (_busy || _fatal || _recovered.isCompleted) return;
    _busy = true;
    _message = reset ? '正在备份并校验...' : '正在重试...';
    notifyListeners();
    if (reset) {
      try {
        await resetStorage(failure);
      } on AndroidMmkvRecoveryException catch (error, stackTrace) {
        _report(error, stackTrace, 'backup_reset');
        _message = '恢复未完成（代码：${error.code}），可重试或关闭应用。';
        _finishAttempt();
        return;
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'backup_reset');
        _message = '备份或重置未完成，原数据未被继续使用。';
        _finishAttempt();
        return;
      }
    }
    try {
      _message = '正在继续启动...';
      notifyListeners();
      await retryStorage();
      _recovered.complete();
    } on AndroidMmkvMigrationException catch (error, stackTrace) {
      _report(error, stackTrace, 'retry');
      failure = error;
      _message = '存储仍不可用，请稍后重试。';
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'retry');
      _fatal = true;
      _message = reset ? '存储修复已完成，但应用初始化失败。请关闭应用后重新启动。' : '应用初始化失败。请关闭应用后重新启动。';
    } finally {
      _finishAttempt();
    }
  }

  void _finishAttempt() {
    _busy = false;
    if (!_recovered.isCompleted) notifyListeners();
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    try {
      reportCallbackError(error, stackTrace, operation);
    } catch (_) {}
  }
}

final class AndroidMmkvRecoveryApp extends StatelessWidget {
  const AndroidMmkvRecoveryApp({required this.controller, super.key});

  final AndroidMmkvRecoveryController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: Constants.appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16865C)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF61D6A6),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: _AndroidMmkvRecoveryPage(controller: controller),
  );
}

final class _AndroidMmkvRecoveryPage extends StatelessWidget {
  const _AndroidMmkvRecoveryPage({required this.controller});

  final AndroidMmkvRecoveryController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final failure = controller.failure;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !controller.busy) controller.closeApplication();
        },
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > 48
                        ? constraints.maxHeight - 48
                        : 0,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.storage_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '存储数据需要修复',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '检测到本地数据存储异常。为避免读取旧数据，应用已暂停启动。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '故障区域：${failure.boxName}\n故障代码：${failure.code}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (controller.message case final message?) ...[
                            const SizedBox(height: 12),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          if (controller.busy) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                          const SizedBox(height: 24),
                          if (!controller.fatal) ...[
                            FilledButton.icon(
                              onPressed: controller.busy
                                  ? null
                                  : controller.retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('重试'),
                            ),
                            if (failure.canReset) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: controller.busy
                                    ? null
                                    : () => _confirmReset(context),
                                icon: const Icon(Icons.restore_rounded),
                                label: const Text('备份并重置此数据'),
                              ),
                            ],
                          ],
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: controller.busy
                                ? null
                                : controller.closeApplication,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('关闭应用'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认重置存储数据？'),
        content: Text(
          '应用会先在私有目录备份并校验，仅重置 '
          '${controller.failure.boxName} 的数据和迁移标记。旧数据不会被自动恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('备份并重置'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.backupResetAndRetry();
    }
  }
}
