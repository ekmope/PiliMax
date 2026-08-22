import 'package:PiliMax/pilimax/pages/setting/pages/crash_report.dart';
import 'package:PiliMax/pilimax/services/crash/crash_report.dart';
import 'package:PiliMax/pilimax/services/crash/crash_report_store.dart';
import 'package:PiliMax/pilimax/services/crash/crash_reporter.dart';
import 'package:PiliMax/pilimax/utils/log_file_export.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class CrashReportHistoryPage extends StatefulWidget {
  const CrashReportHistoryPage({super.key});

  @override
  State<CrashReportHistoryPage> createState() => _CrashReportHistoryPageState();
}

class _CrashReportHistoryPageState extends State<CrashReportHistoryPage> {
  List<CrashReport> _reports = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _reports = CrashReportStore.loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('异常报告历史'),
        actions: [
          if (_reports.isNotEmpty)
            IconButton(
              tooltip: '导出异常报告历史',
              onPressed: _exportAll,
              icon: const Icon(Icons.file_download_outlined),
            ),
          if (_reports.isNotEmpty)
            IconButton(
              tooltip: '清空异常报告历史',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _reports.isEmpty
          ? const Center(child: Text('暂无异常报告'))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                padding.left + 12,
                12,
                padding.right + 12,
                padding.bottom + 24,
              ),
              itemCount: _reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final report = _reports[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(report.exceptionType),
                    subtitle: Text(
                      '${report.crashedAtText}\n${report.rootCause}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CrashReportPage(report: report),
                        ),
                      );
                      if (mounted) setState(_reload);
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _exportAll() async {
    final content = _reports
        .asMap()
        .entries
        .map(
          (entry) =>
              '===== 报告 ${entry.key + 1} =====\n${entry.value.toClipboardText()}',
        )
        .join('\n\n');
    try {
      final shared = await LogFileExport.share(
        content: content,
        filePrefix: 'pilimax_crash_report_history',
        subject: 'PiliMax 异常报告历史',
      );
      if (!shared) {
        SmartDialog.showToast('暂无异常报告历史');
      }
    } catch (_) {
      SmartDialog.showToast('导出异常报告历史失败，请稍后重试');
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空异常报告历史？'),
        content: const Text('所有已保存的异常报告都会被删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CrashReporter.clearHistory();
    if (mounted) setState(_reload);
  }
}
