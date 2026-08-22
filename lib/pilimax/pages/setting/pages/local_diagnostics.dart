import 'dart:async';

import 'package:PiliMax/pilimax/services/local_diagnostics.dart';
import 'package:PiliMax/pilimax/utils/log_file_export.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class LocalDiagnosticsPage extends StatefulWidget {
  const LocalDiagnosticsPage({super.key});

  @override
  State<LocalDiagnosticsPage> createState() => _LocalDiagnosticsPageState();
}

class _LocalDiagnosticsPageState extends State<LocalDiagnosticsPage> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final content = await LocalDiagnostics.readText();
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  void _copy() {
    Utils.copyText(
      _content.isEmpty ? '暂无本地诊断日志' : _content,
      needToast: false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('复制成功'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _export() async {
    try {
      final shared = await LogFileExport.share(
        content: _content,
        filePrefix: 'pilimax_local_diagnostics',
        subject: 'PiliMax 本地诊断日志',
      );
      if (!shared) SmartDialog.showToast('暂无本地诊断日志');
    } catch (_) {
      SmartDialog.showToast('导出诊断日志失败，请稍后重试');
    }
  }

  Future<void> _clear() async {
    if (!await LocalDiagnostics.clear()) {
      SmartDialog.showToast('清空诊断日志失败');
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已清空'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地诊断日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem(onTap: _copy, child: const Text('复制日志')),
              PopupMenuItem(onTap: _export, child: const Text('导出日志（.log）')),
              PopupMenuItem(onTap: _clear, child: const Text('清空日志')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _content.isEmpty
          ? const Center(child: Text('暂无本地诊断日志'))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding.left + 12,
                12,
                padding.right + 12,
                padding.bottom + 24,
              ),
              child: SelectableText(
                _content,
                style: const TextStyle(fontFamily: 'Monospace'),
              ),
            ),
    );
  }
}
