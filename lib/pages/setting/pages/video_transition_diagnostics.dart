import 'dart:async';

import 'package:PiliMax/services/video_transition_diagnostics.dart';
import 'package:PiliMax/utils/utils.dart';

import 'package:flutter/material.dart';

class VideoTransitionDiagnosticsPage extends StatefulWidget {
  const VideoTransitionDiagnosticsPage({super.key});

  @override
  State<VideoTransitionDiagnosticsPage> createState() =>
      _VideoTransitionDiagnosticsPageState();
}

class _VideoTransitionDiagnosticsPageState
    extends State<VideoTransitionDiagnosticsPage> {
  @override
  void initState() {
    super.initState();
    VideoTransitionDiagnostics.enabled.addListener(_refresh);
    VideoTransitionDiagnostics.reports.addListener(_refresh);
    VideoTransitionDiagnostics.currentDisplay.addListener(_refresh);
    VideoTransitionDiagnostics.activeCaptureCount.addListener(_refresh);
    unawaited(VideoTransitionDiagnostics.refreshDisplaySnapshot());
  }

  @override
  void dispose() {
    VideoTransitionDiagnostics.enabled.removeListener(_refresh);
    VideoTransitionDiagnostics.reports.removeListener(_refresh);
    VideoTransitionDiagnostics.currentDisplay.removeListener(_refresh);
    VideoTransitionDiagnostics.activeCaptureCount.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _copyReports() {
    final text = VideoTransitionDiagnostics.exportText();
    Utils.copyText(text.isEmpty ? '暂无视频动画诊断记录' : text);
  }

  void _clearReports() {
    VideoTransitionDiagnostics.clearReports();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('诊断记录已清空'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = VideoTransitionDiagnostics.currentDisplay.value;
    final reports = VideoTransitionDiagnostics.reports.value;
    final activeCount = VideoTransitionDiagnostics.activeCaptureCount.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频动画诊断'),
        actions: [
          const IconButton(
            tooltip: '刷新显示状态',
            onPressed: VideoTransitionDiagnostics.refreshDisplaySnapshot,
            icon: Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '复制诊断记录',
            onPressed: reports.isEmpty ? null : _copyReports,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '清空诊断记录',
            onPressed: reports.isEmpty ? null : _clearReports,
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            value: VideoTransitionDiagnostics.enabled.value,
            onChanged: VideoTransitionDiagnostics.setEnabled,
            secondary: const Icon(Icons.monitor_heart_outlined),
            title: const Text('采集视频动画性能'),
            subtitle: Text(
              activeCount == 0
                  ? '${VideoTransitionDiagnostics.environmentLabel} · 当前空闲'
                  : '${VideoTransitionDiagnostics.environmentLabel} · 正在采集 $activeCount 项',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: const Text('当前显示状态'),
            subtitle: Text(display?.compactDescription ?? '读取中'),
            trailing: display?.preferredDisplayModeId == null
                ? null
                : Text('Mode ${display!.preferredDisplayModeId}'),
          ),
          const Divider(height: 1),
          if (reports.isEmpty)
            const SizedBox(
              height: 240,
              child: Center(child: Text('暂无视频动画诊断记录')),
            )
          else
            for (final report in reports)
              ExpansionTile(
                leading: Icon(_iconFor(report.kind)),
                title: Text(report.title),
                subtitle: Text(report.subtitle),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(report.toExportText()),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  static IconData _iconFor(VideoTransitionDiagnosticKind kind) =>
      switch (kind) {
        VideoTransitionDiagnosticKind.entry => Icons.open_in_full,
        VideoTransitionDiagnosticKind.detailReveal => Icons.layers_outlined,
        VideoTransitionDiagnosticKind.predictiveBack =>
          Icons.swipe_left_outlined,
        VideoTransitionDiagnosticKind.programmaticBack => Icons.arrow_back,
      };
}
