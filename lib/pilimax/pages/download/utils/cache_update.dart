import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

enum _DownloadUpdateAction {
  danmaku('更新弹幕'),
  segments('更新空降片段'),
  volume('更新音量均衡'),
  season('更新合集信息');

  const _DownloadUpdateAction(this.label);
  final String label;
}

/// Shared by completed items and both current collection selection screens.
Future<void> showDownloadUpdateMenu({
  required BuildContext context,
  required DownloadService downloadService,
  required Iterable<BiliDownloadEntryInfo> entries,
}) async {
  final items = entries
      .where((entry) => entry.isCompleted)
      .toList(growable: false);
  if (items.isEmpty) {
    SmartDialog.showToast('请选择已缓存完成的视频');
    return;
  }
  final hasUgc = items.any((entry) => entry.ep == null);
  String label(_DownloadUpdateAction action) =>
      !hasUgc &&
          (action == _DownloadUpdateAction.volume ||
              action == _DownloadUpdateAction.segments)
      ? '更新空降、音量均衡'
      : action.label;
  final action = await showDialog<_DownloadUpdateAction>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('更新缓存信息'),
      children: [
        for (final action in _DownloadUpdateAction.values)
          if (action != _DownloadUpdateAction.season || hasUgc)
            if (hasUgc || action != _DownloadUpdateAction.volume)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(action),
                child: Text(label(action)),
              ),
      ],
    ),
  );
  if (action == null) return;

  var cancelled = false;
  var succeeded = 0;
  var unavailable = 0;
  var failed = 0;
  final progress = ValueNotifier<int>(0);
  SmartDialog.showLoading(
    builder: (context) => Material(
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, current, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('${label(action)} ($current/${items.length})'),
            ],
          ),
        ),
      ),
    ),
    onDismiss: () => cancelled = true,
  );
  try {
    // Bound requests and keep successful items when another selected item fails.
    for (final entry in items) {
      if (cancelled) break;
      DownloadMetadataUpdateResult result;
      try {
        result = switch (action) {
          _DownloadUpdateAction.danmaku =>
            await downloadService.downloadDanmaku(entry: entry, isUpdate: true)
                ? DownloadMetadataUpdateResult.updated
                : DownloadMetadataUpdateResult.failed,
          _DownloadUpdateAction.segments =>
            await downloadService.updateSegments(entry),
          _DownloadUpdateAction.volume => await downloadService.updateVolume(
            entry,
          ),
          _DownloadUpdateAction.season =>
            await downloadService.updateSeasonInfo(entry),
        };
      } catch (_) {
        result = DownloadMetadataUpdateResult.failed;
      }
      switch (result) {
        case DownloadMetadataUpdateResult.updated:
          succeeded++;
        case DownloadMetadataUpdateResult.unavailable:
          unavailable++;
        case DownloadMetadataUpdateResult.failed:
        case DownloadMetadataUpdateResult.removed:
          failed++;
      }
      progress.value++;
    }
  } finally {
    await SmartDialog.dismiss(status: SmartStatus.loading);
    progress.dispose();
  }
  final skipped = items.length - succeeded - unavailable - failed;
  SmartDialog.showToast(
    '更新完成：成功 $succeeded'
    '${unavailable == 0 ? '' : '，暂无数据 $unavailable'}'
    '${failed == 0 ? '' : '，失败 $failed'}'
    '${skipped == 0 ? '' : '，已取消 $skipped'}',
  );
}
