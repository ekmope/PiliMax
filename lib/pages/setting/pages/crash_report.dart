import 'dart:async';
import 'dart:io';

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/services/crash/crash_report.dart';
import 'package:PiliMax/services/crash/crash_report_store.dart';
import 'package:PiliMax/services/crash/crash_reporter.dart';
import 'package:PiliMax/services/route_restore_service.dart';
import 'package:PiliMax/utils/share_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const crashReportRouteName = '/__crash_report__';

class CrashReportStartupGate extends StatefulWidget {
  final CrashReport? initialReport;
  final Widget child;

  const CrashReportStartupGate({
    required this.initialReport,
    required this.child,
    super.key,
  });

  @override
  State<CrashReportStartupGate> createState() => _CrashReportStartupGateState();
}

class _CrashReportStartupGateState extends State<CrashReportStartupGate> {
  bool _shown = false;
  bool _showing = false;
  CrashReport? _resolvedReport;

  @override
  void initState() {
    super.initState();
    _resolvedReport = widget.initialReport;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_bootstrap()),
    );
  }

  @override
  void didUpdateWidget(CrashReportStartupGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReport?.reportId != oldWidget.initialReport?.reportId) {
      _shown = false;
      _resolvedReport = widget.initialReport;
      unawaited(_bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    try {
      if (Platform.isAndroid) {
        for (var attempt = 0; attempt < 5 && mounted; attempt++) {
          try {
            final imported =
                await CrashReporter.importNativeAndResolvePending();
            if (!mounted) return;
            if (imported != null) _resolvedReport = imported;
            break;
          } on MissingPluginException {
            // MainActivity may still be registering the method channel. Pending
            // native files remain untouched if all best-effort retries fail.
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      }

      if (!mounted) return;
      // Route restoration owns the first navigation. Waiting for its asynchronous
      // decision keeps the crash overlay from replacing the restored destination.
      await RouteRestoreService.waitForStartupRestore();
      if (!mounted || _resolvedReport == null) return;
      await _showReportOnce();
    } finally {
      CrashReporter.completeStartupOverlay();
    }
  }

  Future<void> _showReportOnce() async {
    final report = _resolvedReport;
    if (_shown || _showing || report == null) {
      return;
    }
    _showing = true;
    try {
      final navigator = await _waitForNavigator();
      if (!mounted) {
        return;
      }
      if (navigator == null) {
        return;
      }
      _shown = true;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: crashReportRouteName),
          fullscreenDialog: true,
          builder: (_) => CrashReportPage(
            report: report,
            markStoredReportSeenOnContinue: true,
          ),
        ),
      );
    } finally {
      _showing = false;
    }
  }

  Future<NavigatorState?> _waitForNavigator() async {
    for (var attempt = 0; attempt < 30 && mounted; attempt++) {
      final navigator = Get.key.currentState;
      if (navigator != null) return navigator;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CrashReportPage extends StatefulWidget {
  final CrashReport report;
  final bool markStoredReportSeenOnContinue;

  const CrashReportPage({
    required this.report,
    this.markStoredReportSeenOnContinue = false,
    super.key,
  });

  @override
  State<CrashReportPage> createState() => _CrashReportPageState();
}

class _CrashReportPageState extends State<CrashReportPage> {
  bool _showFullStack = false;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final report = widget.report;
    return Scaffold(
      appBar: AppBar(title: const Text('已保存异常报告')),
      body: ListView(
        padding: EdgeInsets.only(
          left: padding.left + 12,
          right: padding.right + 12,
          bottom: padding.bottom + 24,
        ),
        children: [
          const SizedBox(height: 12),
          _SummaryCard(report: report),
          const SizedBox(height: 12),
          _TextSection(
            title: '系统信息',
            icon: Icons.devices_other_outlined,
            text: report.systemInfo,
          ),
          if (report.recentEvents.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TextSection(
              title: '最近应用事件',
              icon: Icons.timeline_outlined,
              text: report.recentEvents.join('\n'),
            ),
          ],
          const SizedBox(height: 12),
          _StackTraceSection(
            stackTrace: report.stackTrace,
            showFullStack: _showFullStack,
            onToggle: () => setState(() => _showFullStack = !_showFullStack),
          ),
          const SizedBox(height: 12),
          _ActionPanel(
            report: report,
            markStoredReportSeenOnContinue:
                widget.markStoredReportSeenOnContinue,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final CrashReport report;

  const _SummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return _card([
      Row(
        spacing: 8,
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          Expanded(
            child: Text(
              report.isFatalCandidate
                  ? 'PiliMax 检测到上次会话的未处理异常。报告中的来源、模块和时间可帮助判断实际触发位置。'
                  : '这是应用主动保存的已处理异常，不代表应用曾因此退出。',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetadataPill(label: '报告 ID', value: report.reportId),
          _MetadataPill(label: '线程', value: report.threadName),
          _MetadataPill(label: '进程', value: report.processName),
          _MetadataPill(label: '时间', value: report.crashedAtText),
          _MetadataPill(label: '来源', value: report.source.label),
          _MetadataPill(label: '级别', value: report.severity.label),
          _MetadataPill(label: '模块', value: report.module),
          if (report.route.isNotEmpty)
            _MetadataPill(label: '路由', value: report.route),
          if (report.reason.isNotEmpty)
            _MetadataPill(label: '原因', value: report.reason),
        ],
      ),
      const SizedBox(height: 16),
      _FieldBlock(
        title: '异常类型',
        value: report.exceptionType,
        color: colorScheme.error,
      ),
      const SizedBox(height: 10),
      _FieldBlock(
        title: '根因',
        value: report.rootCause,
        color: colorScheme.error,
      ),
    ]);
  }
}

class _MetadataPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _FieldBlock extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _FieldBlock({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 6),
        SelectableText(value),
      ],
    );
  }
}

class _TextSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;

  const _TextSection({
    required this.title,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return _card([
      Row(
        spacing: 8,
        children: [
          Icon(icon, size: 21, color: colorScheme.primary),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SelectableText(
        text,
        style: const TextStyle(fontFamily: 'Monospace', fontSize: 13),
      ),
    ]);
  }
}

class _StackTraceSection extends StatelessWidget {
  final String stackTrace;
  final bool showFullStack;
  final VoidCallback onToggle;

  const _StackTraceSection({
    required this.stackTrace,
    required this.showFullStack,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final lines = stackTrace
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final visibleLines = showFullStack ? lines : lines.take(24).toList();
    final colorScheme = ColorScheme.of(context);
    return _card([
      Row(
        spacing: 8,
        children: [
          Icon(Icons.segment_outlined, size: 21, color: colorScheme.error),
          const Expanded(
            child: Text(
              '堆栈信息',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (lines.length > visibleLines.length)
            TextButton(
              onPressed: onToggle,
              child: Text(showFullStack ? '收起' : '展开全部'),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (visibleLines.isEmpty)
        Text('无堆栈信息', style: TextStyle(color: colorScheme.outline))
      else
        SelectableText.rich(
          TextSpan(
            children: [
              for (final line in visibleLines)
                TextSpan(
                  text: '$line\n',
                  style: TextStyle(
                    color: line.contains('package:PiliMax')
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: line.contains('package:PiliMax')
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
            ],
          ),
          style: const TextStyle(fontFamily: 'Monospace', fontSize: 13),
        ),
    ]);
  }
}

class _ActionPanel extends StatelessWidget {
  final CrashReport report;
  final bool markStoredReportSeenOnContinue;

  const _ActionPanel({
    required this.report,
    required this.markStoredReportSeenOnContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _card([
      const Text(
        '报告会尝试遮蔽已知凭据、URI 和本地路径；分享前请检查内容。',
        style: TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => Utils.copyText(report.reportId),
            icon: const Icon(Icons.tag_outlined),
            label: const Text('复制报告 ID'),
          ),
          FilledButton.icon(
            onPressed: () => Utils.copyText(report.toClipboardText()),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制报告'),
          ),
          FilledButton.icon(
            onPressed: () => _showShareOptions(context, report),
            icon: const Icon(Icons.share_outlined),
            label: const Text('分享报告'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              if (markStoredReportSeenOnContinue) {
                await CrashReportStore.markSeen(report.reportId);
              } else {
                await CrashReportStore.remove(report.reportId);
              }
              if (context.mounted) {
                Navigator.of(context).pop();
                SmartDialog.showToast(
                  markStoredReportSeenOnContinue ? '异常报告已保留至历史。' : '异常报告已删除。',
                );
              }
            },
            icon: Icon(
              markStoredReportSeenOnContinue
                  ? Icons.check_outlined
                  : Icons.delete_outline,
            ),
            label: Text(markStoredReportSeenOnContinue ? '继续使用' : '删除报告'),
          ),
        ],
      ),
    ]);
  }

  void _showShareOptions(BuildContext context, CrashReport report) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: Style.dialogFixedConstraints,
        title: const Text('选择分享格式'),
        content: const Text('可以将报告作为纯文本快速发送，也可以作为文本文件附件分享给问题追踪或邮件应用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ShareUtils.shareText(report.toClipboardText());
            },
            child: const Text('作为文本分享'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _shareReportFile(report);
            },
            child: const Text('作为文件分享'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareReportFile(CrashReport report) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'pilimax_crash_report_${report.crashedAtMillis}.txt',
        ),
      );
      await file.writeAsString(report.toClipboardText(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'PiliMax 异常报告',
          sharePositionOrigin: await ShareUtils.sharePositionOrigin,
        ),
      );
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }
}

Widget _card(List<Widget> contents) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: contents,
      ),
    ),
  );
}
